import { test, expect, type APIRequestContext, type Locator, type Page } from "@playwright/test";
import {
  createPreviewReview,
  deleteReview,
  loadPreview,
  loadReview,
  selectInMessageAndPressC,
  messageQuoteHighlights,
  expectPaintedMessageQuote,
} from "./helpers";

// ============================================================
// Sub-threads — comments on a passage of a comment or a reply
// ============================================================
//
// Mirrors crit's test/e2e/tests/subthreads.spec.ts. Selecting a passage
// inside one message body and pressing c opens a composer under that message;
// the sub-thread then nests there, its quote on top and the passage
// highlighted in the message. Sub-threads are full threads: replies, resolve,
// delete, and their own sub-threads at any depth.
//
// Reviews are shared through the API by a signed-in owner, who then opens
// them in the browser: every message belongs to the viewer, so the resolve,
// edit and delete buttons are there. Messages are addressed by the
// external_id they were shared with.

const BASE_URL = `http://127.0.0.1:${process.env.CRIT_WEB_TEST_PORT || "4003"}`;

const PLAN = { path: "plan.md", content: "# Plan\n\nStep one of the plan.\n\nStep two of the plan.\n" };
const SERVER = {
  path: "server.go",
  content: 'package main\n\nimport "encoding/json"\n\nfunc respondJSON() {\n\tjson.Marshal(nil)\n}\n',
};

type Message = {
  id: string;
  external_id?: string;
  anchor_comment_id?: string | null;
  body: string;
  quote?: string | null;
  quote_offset?: number | null;
  resolved?: boolean;
  replies?: Message[];
  sub_threads?: Message[];
};

type Shared = { token: string; deleteToken: string; userId: string; ids: Record<string, string> };

// Share a review as a new signed-in user (owning every message of the
// payload) and sign the browser in as that user.
async function shareAsOwner(
  request: APIRequestContext,
  page: Page,
  payload: Record<string, unknown>,
): Promise<Shared> {
  const seed = await request.post(`${BASE_URL}/api/test/seed-user`, { data: { name: "Sub Owner" } });
  expect(seed.status()).toBe(200);
  const { user_id: userId, token: bearer } = await seed.json();
  const own = (messages: unknown) =>
    ((messages as Record<string, unknown>[] | undefined) || []).map((m) => ({
      ...m,
      user_id: userId,
      replies: ((m.replies as Record<string, unknown>[] | undefined) || []).map((r) => ({ ...r, user_id: userId })),
    }));
  const res = await request.post(`${BASE_URL}/api/reviews`, {
    headers: { Authorization: `Bearer ${bearer}` },
    data: {
      files: [PLAN],
      ...payload,
      comments: own(payload.comments),
      review_comments: own(payload.review_comments),
      sub_threads: own(payload.sub_threads),
    },
  });
  expect(res.status()).toBe(201);
  const { url, delete_token: deleteToken } = await res.json();
  const token = (url as string).split("/r/")[1];
  await page.goto(`/test/login-as/${userId}`);
  return { token, deleteToken, userId, ids: await idsByExternalId(request, token) };
}

// The review's messages as crit fetches them: threads, their replies, and
// the sub-threads nested under each message.
async function threads(request: APIRequestContext, token: string): Promise<Message[]> {
  const res = await request.get(`${BASE_URL}/api/reviews/${token}/comments`);
  expect(res.status()).toBe(200);
  return res.json();
}

// Every comment and sub-thread, flat (replies stay in their thread).
async function allComments(request: APIRequestContext, token: string): Promise<Message[]> {
  const out: Message[] = [];
  const walk = (m: Message) => {
    out.push(m);
    (m.replies || []).forEach((r) => (r.sub_threads || []).forEach(walk));
    (m.sub_threads || []).forEach(walk);
  };
  (await threads(request, token)).forEach(walk);
  return out;
}

async function idsByExternalId(request: APIRequestContext, token: string) {
  const ids: Record<string, string> = {};
  const walk = (m: Message) => {
    if (m.external_id) ids[m.external_id] = m.id;
    (m.replies || []).forEach(walk);
    (m.sub_threads || []).forEach(walk);
  };
  (await threads(request, token)).forEach(walk);
  return ids;
}

// A line thread on the plan, with optional replies.
function planThread(externalId: string, body: string, replies: { external_id: string; body: string }[] = []) {
  return { external_id: externalId, file: PLAN.path, start_line: 3, end_line: 3, scope: "line", body, replies };
}

function subThread(
  externalId: string,
  parent: string,
  body: string,
  quote: string,
  quoteOffset: number,
  extra: Record<string, unknown> = {},
) {
  return { external_id: externalId, parent_external_id: parent, body, quote, quote_offset: quoteOffset, ...extra };
}

// Inline cards and replies in the document (not their comments-panel copies).
function card(page: Page, id: string): Locator {
  return page.locator(`#document-renderer .comment-card[data-comment-id="${id}"]`);
}

function reply(page: Page, id: string): Locator {
  return page.locator(`#document-renderer .comment-reply[data-reply-id="${id}"]`);
}

// The sub-thread cards directly under a card's body or a reply.
function nestedCards(message: Locator): Locator {
  return message.locator(":scope > .subthreads > .comment-block > .comment-card");
}

function composerUnder(message: Locator): Locator {
  return message.locator(":scope > .subthreads > .subthread-composer");
}

async function openPlan(page: Page, token: string) {
  await loadReview(page, token);
  await expect(page.locator("#document-renderer .comment-card").first()).toBeVisible();
}

test.describe("Sub-threads", () => {
  let deleteToken: string | null = null;

  test("preview mode leaves sub-threads out: it has no message to nest them under", async ({ page, request }) => {
    const review = await createPreviewReview(request, {
      comments: [{ body: "Tighten this heading copy", css_selector: "#hero", tag_chain: ["body", "main", "h1"] }],
    });
    deleteToken = review.deleteToken;
    const [pinned] = await threads(request, review.token);
    const seeded = await request.post(`${BASE_URL}/api/reviews/${review.token}/seed-sub-thread/${pinned.id}`, {
      data: { body: "A sub-thread on the pin", quote: "Tighten", quote_offset: 0 },
    });
    expect(seeded.status()).toBe(200);

    await loadPreview(page, review.token);
    const cards = page.locator("#critPreviewPanelBody .comment-card");
    await expect(cards.filter({ hasText: "Tighten this heading copy" })).toBeVisible({ timeout: 10_000 });
    await expect(cards).toHaveCount(1);
    await expect(page.locator("#critPreviewPanelBody")).not.toContainText("A sub-thread on the pin");
    await expect(page.locator("#commentsPanelCountBadge")).toHaveText("1");
  });

  test.afterEach(async ({ request }) => {
    if (deleteToken) await deleteReview(request, deleteToken);
    deleteToken = null;
  });

  test("c on a passage of a reply opens a composer under it; the sub-thread nests there, quote shown and highlighted", async ({ page, request }) => {
    const shared = await shareAsOwner(request, page, {
      comments: [planThread("c_root", "Which option?", [{ external_id: "r_answer", body: "Option A is faster. Option B is safer." }])],
    });
    deleteToken = shared.deleteToken;
    const answerId = shared.ids.r_answer;
    await openPlan(page, shared.token);

    const replyEl = reply(page, answerId);
    await selectInMessageAndPressC(page, replyEl.locator(":scope > .reply-body"), "Option B is safer");

    const composer = composerUnder(replyEl);
    await expect(composer).toBeVisible();
    await expect(composer.locator(".subthread-quote")).toHaveText("Option B is safer");
    const textarea = composer.locator("textarea");
    await expect(textarea).toBeFocused();
    // The passage is highlighted while the comment is written.
    await expect.poll(() => messageQuoteHighlights(page)).toEqual(["Option B is safer"]);

    await textarea.fill("Why is B safer?");
    await composer.locator(".comment-form-actions .btn-primary").click();
    await expect(composer).toHaveCount(0);

    const sub = nestedCards(replyEl);
    await expect(sub).toHaveCount(1);
    await expect(sub.locator(":scope > .subthread-quote")).toHaveText("Option B is safer");
    await expect(sub.locator(":scope > .comment-body")).toHaveText("Why is B safer?");
    // A sub-thread is anchored to a passage, not to lines.
    await expect(sub.locator(":scope > .comment-header .comment-line-ref")).toHaveCount(0);
    await expect.poll(() => messageQuoteHighlights(page)).toEqual(["Option B is safer"]);
    await expectPaintedMessageQuote(page);

    // Stored as a sub-thread of the reply, with the passage's offset in the
    // reply's rendered text.
    const stored = (await allComments(request, shared.token)).find((c) => c.anchor_comment_id === answerId);
    expect(stored).toMatchObject({ body: "Why is B safer?", quote: "Option B is safer", quote_offset: 20 });

    // The header count and the comments panel count it as an open comment;
    // the panel mirrors it read-only under the reply and highlights the
    // passage in its copy too.
    await expect(page.locator("#commentCountNumber")).toHaveText("2");
    await page.keyboard.press("Shift+C");
    const panelSub = page.locator(`#commentsPanel .comment-reply[data-reply-id="${answerId}"] > .subthreads .comment-card`);
    await expect(panelSub).toContainText("Why is B safer?");
    await expect(panelSub.locator(".reply-form")).toHaveCount(0);
    await expect(page.locator('#commentsFilterPill .crit-toggle-btn[data-filter="open"] .filter-count')).toHaveText("2");
    await expect.poll(() => messageQuoteHighlights(page)).toEqual(["Option B is safer", "Option B is safer"]);
  });

  test("a passage of the root comment nests before the replies; Escape closes an empty composer; the sub-thread takes replies", async ({ page, request }) => {
    const shared = await shareAsOwner(request, page, {
      comments: [planThread("c_root", "Rename the helper and add a test.", [{ external_id: "r_done", body: "Done." }])],
    });
    deleteToken = shared.deleteToken;
    await openPlan(page, shared.token);

    const rootCard = card(page, shared.ids.c_root);
    const rootBody = rootCard.locator(":scope > .comment-body");
    const composer = composerUnder(rootCard);

    await selectInMessageAndPressC(page, rootBody, "Rename the helper");
    await expect(composer.locator("textarea")).toBeFocused();
    await composer.locator("textarea").press("Escape");
    await expect(composer).toHaveCount(0);
    await expect.poll(() => messageQuoteHighlights(page)).toEqual([]);

    await selectInMessageAndPressC(page, rootBody, "add a test");
    await expect(composer.locator(".subthread-quote")).toHaveText("add a test");
    await composer.locator("textarea").fill("Which test?");
    await composer.locator("textarea").press("Control+Enter");

    const sub = nestedCards(rootCard);
    await expect(sub).toContainText("Which test?");
    // Under the root's body, before its replies.
    expect(await rootCard.evaluate((el) => {
      const kids = Array.from(el.children).map((child) => child.className);
      return kids.indexOf("subthreads") === kids.indexOf("comment-body") + 1 &&
        kids.indexOf("subthreads") < kids.indexOf("comment-replies");
    })).toBe(true);

    // A reply in the sub-thread stays in the sub-thread.
    await sub.locator(":scope > .reply-form .reply-input").click();
    const replyBox = sub.locator(":scope > .reply-form .reply-textarea");
    await expect(replyBox).toBeFocused();
    await replyBox.fill("The helper unit test.");
    await sub.locator(":scope > .reply-form .reply-form-buttons .btn-primary").click();
    await expect(sub.locator(":scope > .comment-replies > .comment-reply")).toHaveCount(1);
    await expect(sub.locator(":scope > .comment-replies .reply-body")).toHaveText("The helper unit test.");
    await expect(rootCard.locator(":scope > .comment-replies > .comment-reply")).toHaveCount(1);
  });

  test("a message of a sub-thread takes its own sub-thread, at any depth, with the same indent at every level", async ({ page, request }) => {
    const shared = await shareAsOwner(request, page, {
      comments: [planThread("c_root", "Root comment body.", [{ external_id: "r_answer", body: "First level text here." }])],
      sub_threads: [
        subThread("s_first", "r_answer", "Second level text here.", "First level", 0),
        subThread("s_second", "s_first", "Third level text here.", "Second level", 0),
      ],
    });
    deleteToken = shared.deleteToken;
    const { c_root: rootId, s_first: firstId, s_second: secondId } = shared.ids;
    await openPlan(page, shared.token);

    await selectInMessageAndPressC(page, card(page, secondId).locator(":scope > .comment-body"), "Third level");
    const composer = composerUnder(card(page, secondId));
    await expect(composer.locator("textarea")).toBeFocused();
    await composer.locator("textarea").fill("Fourth level text here.");
    await composer.locator("textarea").press("Control+Enter");
    const third = nestedCards(card(page, secondId));
    await expect(third).toContainText("Fourth level text here.");

    await expect(page.locator("#document-renderer .subthreads")).toHaveCount(3);
    await expect(page.locator("#document-renderer .subthreads .subthreads .subthreads")).toHaveCount(1);

    const box = async (loc: Locator) => (await loc.boundingBox())!;
    const b0 = await box(card(page, rootId));
    const b1 = await box(card(page, firstId));
    const b2 = await box(card(page, secondId));
    const b3 = await box(third);
    expect(b1.x - b0.x, "first level is indented").toBeGreaterThan(10);
    // The second and third levels both nest under a comment body: same
    // indent, same right margin, no special case by depth.
    expect(b2.x - b1.x, "second level is indented").toBeGreaterThan(10);
    expect(Math.abs((b3.x - b2.x) - (b2.x - b1.x)), "third level takes the same indent").toBeLessThanOrEqual(1);
    const rightGap = (outer: { x: number; width: number }, inner: { x: number; width: number }) =>
      (outer.x + outer.width) - (inner.x + inner.width);
    expect(rightGap(b1, b2), "second level keeps a right margin").toBeGreaterThan(0);
    expect(Math.abs(rightGap(b2, b3) - rightGap(b1, b2)), "third level keeps the same right margin").toBeLessThanOrEqual(1);
    await expect(page.locator("#document-renderer .subthreads .subthreads .subthreads"), "third level keeps its thread line")
      .toHaveCSS("border-left-style", "solid");

    expect((await messageQuoteHighlights(page)).sort()).toEqual(["First level", "Second level", "Third level"]);
  });

  test("a sub-thread resolves alone; while open it keeps its resolved parent shown, hide-resolved included", async ({ page, request }) => {
    const shared = await shareAsOwner(request, page, {
      comments: [{ ...planThread("c_root", "Root to resolve."), resolved: true }],
      sub_threads: [subThread("s_open", "c_root", "Still open here.", "Root", 0)],
    });
    deleteToken = shared.deleteToken;
    const { c_root: rootId, s_open: openId } = shared.ids;
    await openPlan(page, shared.token);

    const rootCard = card(page, rootId);
    const subCard = card(page, openId);
    // One open comment: the sub-thread.
    await expect(page.locator("#commentCountNumber")).toHaveText("1");
    await expect(rootCard.locator("xpath=..")).toHaveClass(/has-open-subthreads/);
    await expect(rootCard).not.toHaveClass(/collapsed/);
    await expect(subCard).toBeVisible();

    await page.keyboard.press("h");
    await expect(rootCard).toBeVisible();
    await expect(subCard).toBeVisible();

    // Resolving the sub-thread: nothing open is left, and the resolved parent
    // hides with the rest.
    await subCard.hover();
    await subCard.locator(":scope > .comment-header .resolve-btn").click();
    await expect(page.locator("#commentCountNumber")).toHaveText("✓");
    await expect(rootCard).toBeHidden();

    await page.keyboard.press("h");
    await expect(rootCard).toBeVisible();
    await expect(rootCard).toHaveClass(/collapsed/);

    // Unresolving the parent leaves the sub-thread resolved.
    await rootCard.locator(":scope > .comment-header .comment-collapse-btn").click();
    await rootCard.hover();
    await rootCard.locator(':scope > .comment-header .comment-actions button[title="Unresolve"]').click();
    await expect(page.locator("#commentCountNumber")).toHaveText("1");
    const stored = await allComments(request, shared.token);
    expect(stored.find((c) => c.id === rootId)?.resolved ?? false).toBe(false);
    expect(stored.find((c) => c.id === openId)?.resolved).toBe(true);
  });

  test("deleting a message with sub-threads asks first, with their number; without any it stays immediate", async ({ page, request }) => {
    const shared = await shareAsOwner(request, page, {
      comments: [planThread("c_root", "Root with replies.", [
        { external_id: "r_answer", body: "Alpha beta gamma delta." },
        { external_id: "r_lone", body: "A reply with nothing under it." },
      ])],
      sub_threads: [
        subThread("s_alpha", "r_answer", "On alpha.", "Alpha", 0),
        subThread("s_gamma", "r_answer", "On gamma.", "gamma", 11),
        subThread("s_deeper", "s_alpha", "Deeper.", "On alpha", 0),
      ],
    });
    deleteToken = shared.deleteToken;
    await openPlan(page, shared.token);

    const replyEl = reply(page, shared.ids.r_answer);
    const deleteReplyEl = async (el: Locator) => {
      await el.hover();
      await el.locator(":scope > .reply-header .delete-btn").click();
    };
    await expect(replyEl.locator(".subthreads .comment-card")).toHaveCount(3);

    // Dismissed: nothing is deleted.
    const messages: string[] = [];
    page.once("dialog", (d) => { messages.push(d.message()); void d.dismiss(); });
    await deleteReplyEl(replyEl);
    await expect.poll(() => messages.length).toBe(1);
    expect(messages[0]).toContain("3 sub-threads");
    await expect(replyEl.locator(".subthreads .comment-card")).toHaveCount(3);

    // Accepted: the reply goes, its sub-threads with it.
    page.once("dialog", (d) => { messages.push(d.message()); void d.accept(); });
    await deleteReplyEl(replyEl);
    await expect(replyEl).toHaveCount(0);
    await expect(page.locator("#document-renderer .subthreads")).toHaveCount(0);
    await expect.poll(async () => (await allComments(request, shared.token)).filter((c) => c.anchor_comment_id).length).toBe(0);
    expect(messages).toHaveLength(2);
    await expect(page.locator("#commentCountNumber")).toHaveText("1");

    // No sub-thread under it: no question asked.
    await deleteReplyEl(reply(page, shared.ids.r_lone));
    await expect(reply(page, shared.ids.r_lone)).toHaveCount(0);
    expect(messages).toHaveLength(2);
  });

  test("sub-threads and their highlighted passages survive a reload", async ({ page, request }) => {
    const shared = await shareAsOwner(request, page, {
      comments: [planThread("c_root", "Keep the cache small.")],
    });
    deleteToken = shared.deleteToken;
    const rootId = shared.ids.c_root;
    await openPlan(page, shared.token);

    await selectInMessageAndPressC(page, card(page, rootId).locator(":scope > .comment-body"), "the cache");
    await composerUnder(card(page, rootId)).locator("textarea").fill("How small?");
    await composerUnder(card(page, rootId)).locator("textarea").press("Control+Enter");
    await expect(nestedCards(card(page, rootId))).toContainText("How small?");
    await expect.poll(() => messageQuoteHighlights(page)).toEqual(["the cache"]);

    await openPlan(page, shared.token);
    await expect(nestedCards(card(page, rootId))).toContainText("How small?");
    await expect(nestedCards(card(page, rootId)).locator(":scope > .subthread-quote")).toHaveText("the cache");
    await expect.poll(() => messageQuoteHighlights(page)).toEqual(["the cache"]);
  });

  test("a passage of a review-level comment opens a sub-thread in the review conversation", async ({ page, request }) => {
    const shared = await shareAsOwner(request, page, {
      review_comments: [{ external_id: "c_general", scope: "review", body: "Ship it after the docs pass.", replies: [{ external_id: "r_general", body: "Agreed." }] }],
    });
    deleteToken = shared.deleteToken;
    const rootId = shared.ids.c_general;
    await loadReview(page, shared.token);

    const section = page.locator("#reviewConversation");
    const rootCard = section.locator(`.comment-card[data-comment-id="${rootId}"]`);
    // Each reply shows once.
    await expect(rootCard.locator(".comment-reply")).toHaveCount(1);
    await selectInMessageAndPressC(page, rootCard.locator(":scope > .comment-body"), "the docs pass");
    const composer = composerUnder(rootCard);
    await expect(composer.locator("textarea")).toBeFocused();
    await composer.locator("textarea").fill("Which docs?");
    await composer.locator("textarea").press("Control+Enter");
    await expect(nestedCards(rootCard)).toContainText("Which docs?");
    await expect(section.locator(".review-conversation-header .count")).toHaveText("2");
    await expect.poll(() => messageQuoteHighlights(page)).toEqual(["the docs pass"]);

    const listed = await allComments(request, shared.token);
    const subId = listed.find((c) => c.anchor_comment_id === rootId)!.id;
    expect(listed.find((c) => c.id === subId)).toMatchObject({ body: "Which docs?", quote: "the docs pass" });

    // Edited in place, with the review conversation's editor.
    const subCard = section.locator(`.comment-card[data-comment-id="${subId}"]`);
    await subCard.hover();
    await subCard.locator(':scope > .comment-header .comment-actions button[title="Edit"]').click();
    const editor = rootCard.locator(`:scope > .subthreads .comment-form[data-form-key="review:edit:${subId}"]`);
    await expect(editor.locator("textarea")).toBeFocused();
    await editor.locator("textarea").fill("Which docs, exactly?");
    await editor.getByRole("button", { name: "Save" }).click();
    await expect(editor).toHaveCount(0);
    await expect(nestedCards(rootCard).locator(":scope > .comment-body")).toHaveText("Which docs, exactly?");

    // Deleting the comment takes its sub-thread, after saying so.
    const messages: string[] = [];
    page.once("dialog", (d) => { messages.push(d.message()); void d.accept(); });
    await rootCard.hover();
    await rootCard.locator(":scope > .comment-header .delete-btn").click();
    await expect(rootCard).toHaveCount(0);
    expect(messages[0]).toContain("1 sub-thread");
    await expect.poll(async () => (await allComments(request, shared.token)).length).toBe(0);
  });

  test("a sub-thread on a reply of a code file thread", async ({ page, request }) => {
    const shared = await shareAsOwner(request, page, {
      files: [PLAN, SERVER],
      comments: [{
        external_id: "c_code", file: SERVER.path, start_line: 3, end_line: 3, scope: "line", body: "Why this import?",
        replies: [{ external_id: "r_code", body: "It formats the JSON body for respondJSON." }],
      }],
    });
    deleteToken = shared.deleteToken;
    const answerId = shared.ids.r_code;
    await loadReview(page, shared.token);

    const replyEl = reply(page, answerId);
    await selectInMessageAndPressC(page, replyEl.locator(":scope > .reply-body"), "the JSON body");
    const composer = composerUnder(replyEl);
    await expect(composer.locator("textarea")).toBeFocused();
    await composer.locator("textarea").fill("Only the body?");
    await composer.locator(".comment-form-actions .btn-primary").click();

    const sub = nestedCards(replyEl);
    await expect(sub).toContainText("Only the body?");
    await expect(sub.locator(":scope > .subthread-quote")).toHaveText("the JSON body");
    await expect.poll(() => messageQuoteHighlights(page)).toEqual(["the JSON body"]);
    const stored = (await allComments(request, shared.token)).find((c) => c.anchor_comment_id === answerId);
    expect(stored).toMatchObject({ quote: "the JSON body", quote_offset: 11 });
    // The file's tree badge counts the open sub-thread.
    await expect(page.locator('.tree-file[data-path="server.go"] .tree-comment-badge')).toHaveText("2");
  });

  test("a selection running from a message onto the document keeps commenting on the document", async ({ page, request }) => {
    const shared = await shareAsOwner(request, page, { comments: [planThread("c_root", "Overflowing selection.")] });
    deleteToken = shared.deleteToken;
    await openPlan(page, shared.token);

    const rootCard = card(page, shared.ids.c_root);
    await rootCard.evaluate((cardEl) => {
      // First text node of `el` holding some text.
      const firstText = (el: Element) => {
        const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
        let t: Node | null;
        while ((t = walker.nextNode()) && (t as Text).data.trim().length < 3);
        return t as Text;
      };
      const body = cardEl.querySelector(":scope > .comment-body")!;
      // The next document line with text, below the card.
      const next = Array.from(document.querySelectorAll(".line-block .line-content"))
        .find((el) => !!(cardEl.compareDocumentPosition(el) & Node.DOCUMENT_POSITION_FOLLOWING) && !!el.textContent!.trim())!;
      const range = document.createRange();
      const end = firstText(next);
      range.setStart(firstText(body), 0);
      range.setEnd(end, end.data.search(/\S/) + 3);
      const selection = window.getSelection()!;
      selection.removeAllRanges();
      selection.addRange(range);
    });
    await page.keyboard.press("c");

    await expect(page.locator('#document-renderer .comment-form[data-form-key^="plan.md:"] textarea')).toBeVisible();
    await expect(page.locator(".subthread-composer")).toHaveCount(0);
  });

  test("a sub-thread body can be edited in place", async ({ page, request }) => {
    const shared = await shareAsOwner(request, page, {
      comments: [planThread("c_root", "Edit the nested one.")],
      sub_threads: [subThread("s_edit", "c_root", "Original sub-thread body", "nested one", 9)],
    });
    deleteToken = shared.deleteToken;
    const { c_root: rootId, s_edit: subId } = shared.ids;
    await openPlan(page, shared.token);

    const subCard = card(page, subId);
    await subCard.hover();
    await subCard.locator(':scope > .comment-header .comment-actions button[title="Edit"]').click();
    const editor = card(page, rootId).locator(":scope > .subthreads .comment-form");
    await expect(editor.locator(".comment-form-header")).toHaveText("Editing comment");
    await expect(editor.locator("textarea")).toHaveValue("Original sub-thread body");
    await editor.locator("textarea").fill("Edited sub-thread body");
    await editor.getByRole("button", { name: "Update" }).click();

    await expect(editor).toHaveCount(0);
    await expect(nestedCards(card(page, rootId)).locator(":scope > .comment-body")).toHaveText("Edited sub-thread body");
    await expect(card(page, subId).locator(":scope > .subthread-quote")).toHaveText("nested one");
    expect((await allComments(request, shared.token)).find((c) => c.id === subId)?.body).toBe("Edited sub-thread body");
  });

  test("another tab sees sub-threads come, resolve and go with their message; an open composer survives", async ({ page, request }) => {
    const shared = await shareAsOwner(request, page, {
      comments: [planThread("c_root", "Keep typing through refreshes.", [{ external_id: "r_doomed", body: "This reply will be deleted." }])],
    });
    deleteToken = shared.deleteToken;
    const { c_root: rootId, r_doomed: doomedId } = shared.ids;
    const other = await page.context().newPage();
    await openPlan(page, shared.token);
    await openPlan(other, shared.token);

    // This tab writes in a composer under the root body.
    const rootCard = card(page, rootId);
    await selectInMessageAndPressC(page, rootCard.locator(":scope > .comment-body"), "through refreshes");
    const textarea = composerUnder(rootCard).locator("textarea");
    await textarea.pressSequentially("Draft in progress");

    // The other tab adds a sub-thread on the reply: both tabs show it, and
    // the composer keeps its text and focus through the rebuilt card.
    await selectInMessageAndPressC(other, reply(other, doomedId).locator(":scope > .reply-body"), "will be deleted");
    await composerUnder(reply(other, doomedId)).locator("textarea").fill("Why delete it?");
    await composerUnder(reply(other, doomedId)).locator("textarea").press("Control+Enter");
    await expect(nestedCards(reply(page, doomedId))).toContainText("Why delete it?");
    await expect(textarea).toHaveValue("Draft in progress");
    await expect(textarea).toBeFocused();
    await expect(composerUnder(rootCard).locator(".subthread-quote")).toHaveText("through refreshes");
    await expect(page.locator("#commentCountNumber")).toHaveText("2");

    // Resolved in the other tab, collapsed here.
    const subId = (await allComments(request, shared.token)).find((c) => c.anchor_comment_id === doomedId)!.id;
    await card(other, subId).hover();
    await card(other, subId).locator(":scope > .comment-header .resolve-btn").click();
    await expect(card(page, subId)).toHaveClass(/resolved-card/);
    await expect(card(page, subId)).toHaveClass(/collapsed/);

    // The other tab deletes the reply: its sub-thread goes from this tab too.
    other.once("dialog", (d) => void d.accept());
    await reply(other, doomedId).hover();
    await reply(other, doomedId).locator(":scope > .reply-header .delete-btn").click();
    await expect(reply(page, doomedId)).toHaveCount(0);
    await expect(card(page, subId)).toHaveCount(0);
    await expect(page.locator("#commentCountNumber")).toHaveText("1");

    // The composer, under the root, carries on.
    await textarea.pressSequentially(", done.");
    await textarea.press("Control+Enter");
    await expect(nestedCards(rootCard)).toContainText("Draft in progress, done.");
    await expect(nestedCards(card(other, rootId))).toContainText("Draft in progress, done.");
    await other.close();
  });

  test("hide-resolved keeps a resolved sub-thread hidden when another tab changes its thread", async ({ page, request }) => {
    const shared = await shareAsOwner(request, page, {
      files: [PLAN, SERVER],
      comments: [
        planThread("c_doc", "Doc thread.", [{ external_id: "r_doc", body: "Doc answer." }]),
        {
          external_id: "c_code", file: SERVER.path, start_line: 3, end_line: 3, scope: "line", body: "Code thread.",
          replies: [{ external_id: "r_code", body: "Code answer." }],
        },
      ],
      sub_threads: [
        subThread("s_doc", "r_doc", "Settled doc point.", "Doc", 0, { resolved: true }),
        subThread("s_code", "r_code", "Settled code point.", "Code", 0, { resolved: true }),
      ],
    });
    deleteToken = shared.deleteToken;
    const { c_doc: docId, c_code: codeId, s_doc: subDocId, s_code: subCodeId } = shared.ids;
    const other = await page.context().newPage();
    await loadReview(page, shared.token);
    await loadReview(other, shared.token);

    await page.keyboard.press("h");
    await expect(card(page, subDocId)).toBeHidden();
    await expect(card(page, subCodeId)).toBeHidden();

    // The other tab replies in the document thread (this tab rebuilds its
    // reply list) and adds a sub-thread in the code thread (this tab rebuilds
    // the code file's threads).
    await card(other, docId).locator(":scope > .reply-form .reply-input").click();
    await card(other, docId).locator(":scope > .reply-form .reply-textarea").fill("Another answer.");
    await card(other, docId).locator(":scope > .reply-form .reply-form-buttons .btn-primary").click();
    await selectInMessageAndPressC(other, card(other, codeId).locator(":scope > .comment-body"), "Code thread");
    await composerUnder(card(other, codeId)).locator("textarea").fill("On the code thread.");
    await composerUnder(card(other, codeId)).locator("textarea").press("Control+Enter");

    await expect(card(page, docId).locator(":scope > .comment-replies > .comment-reply")).toHaveCount(2);
    await expect(nestedCards(card(page, codeId))).toContainText("On the code thread.");
    await expect(card(page, subDocId)).toBeHidden();
    await expect(card(page, subCodeId)).toBeHidden();

    await page.keyboard.press("h");
    await expect(card(page, subDocId)).toBeVisible();
    await expect(card(page, subCodeId)).toBeVisible();
    await other.close();
  });

  test("a reply being written survives another tab's change in its thread", async ({ page, request }) => {
    const shared = await shareAsOwner(request, page, {
      comments: [planThread("c_root", "Root body.", [{ external_id: "r_answer", body: "An answer here." }])],
      review_comments: [
        { external_id: "c_general", scope: "review", body: "General thread.", replies: [] },
        { external_id: "c_other", scope: "review", body: "Other general thread.", replies: [] },
      ],
      sub_threads: [subThread("s_open", "r_answer", "Open point.", "answer", 3)],
    });
    deleteToken = shared.deleteToken;
    const { c_root: rootId, s_open: subId, c_general: generalId, c_other: otherGeneralId } = shared.ids;
    const other = await page.context().newPage();
    await openPlan(page, shared.token);
    await openPlan(other, shared.token);

    // A reply half-written under the root thread; the other tab resolves the
    // sub-thread in that thread, which rebuilds it here.
    const replyBox = (scope: Locator) => scope.locator(":scope > .reply-form .reply-textarea");
    await card(page, rootId).locator(":scope > .reply-form .reply-input").click();
    await replyBox(card(page, rootId)).pressSequentially("Half-written reply");
    await card(other, subId).hover();
    await card(other, subId).locator(":scope > .comment-header .resolve-btn").click();
    await expect(card(page, subId)).toHaveClass(/resolved-card/);
    await expect(replyBox(card(page, rootId))).toHaveValue("Half-written reply");
    await expect(replyBox(card(page, rootId))).toBeFocused();
    await replyBox(card(page, rootId)).pressSequentially(", finished.");
    await card(page, rootId).locator(":scope > .reply-form .reply-form-buttons .btn-primary").click();
    await expect(card(page, rootId).locator(":scope > .comment-replies > .comment-reply")).toHaveCount(2);
    await expect(card(page, rootId).locator(":scope > .comment-replies")).toContainText("Half-written reply, finished.");

    // Same in the review conversation, rebuilt whole by the other tab's sub-thread.
    const section = (p: Page) => p.locator("#reviewConversation");
    const general = section(page).locator(`.comment-card[data-comment-id="${generalId}"]`);
    await general.locator(":scope > .reply-form .reply-input").click();
    await replyBox(general).pressSequentially("Typing in the conversation");
    const otherGeneral = section(other).locator(`.comment-card[data-comment-id="${otherGeneralId}"]`);
    await selectInMessageAndPressC(other, otherGeneral.locator(":scope > .comment-body"), "Other general");
    await composerUnder(otherGeneral).locator("textarea").fill("A sub-thread meanwhile.");
    await composerUnder(otherGeneral).locator("textarea").press("Control+Enter");
    await expect(nestedCards(section(page).locator(`.comment-card[data-comment-id="${otherGeneralId}"]`))).toContainText("A sub-thread meanwhile.");
    await expect(replyBox(general)).toHaveValue("Typing in the conversation");
    await expect(replyBox(general)).toBeFocused();
    await other.close();
  });

  test("a sub-thread on a message deleted without notice closes its composer with the server's message", async ({ page, request }) => {
    const shared = await shareAsOwner(request, page, {
      comments: [planThread("c_root", "Root stays.", [{ external_id: "r_gone", body: "This reply goes away." }])],
    });
    deleteToken = shared.deleteToken;
    await openPlan(page, shared.token);

    const replyEl = reply(page, shared.ids.r_gone);
    await selectInMessageAndPressC(page, replyEl.locator(":scope > .reply-body"), "goes away");
    await composerUnder(replyEl).locator("textarea").fill("Too late.");

    // A re-share drops the reply; nothing tells this tab.
    const reshared = await request.put(`${BASE_URL}/api/reviews/${shared.token}`, {
      data: { delete_token: shared.deleteToken, files: [PLAN], comments: [planThread("c_root", "Root stays.")] },
    });
    expect(reshared.status()).toBe(200);

    await composerUnder(replyEl).locator("textarea").press("Control+Enter");
    await expect(page.locator(".mini-toast", { hasText: "The commented message no longer exists." })).toBeVisible();
    await expect(page.locator(".subthread-composer")).toHaveCount(0);
    // The comments are synced again: the reply is gone here too.
    await expect(page.locator("#document-renderer .comment-reply")).toHaveCount(0);
    await expect(page.locator("#document-renderer .comment-card")).toHaveCount(1);
  });

  test("a viewer who may not comment gets no composer", async ({ browser, request }) => {
    const seed = await request.post(`${BASE_URL}/api/test/seed-user`, { data: { name: "Policy Owner" } });
    const { token: bearer } = await seed.json();
    const res = await request.post(`${BASE_URL}/api/reviews`, {
      headers: { Authorization: `Bearer ${bearer}` },
      data: { files: [PLAN], comments: [planThread("c_root", "Members only here.")], comment_policy: "logged_in_only" },
    });
    expect(res.status()).toBe(201);
    const { url, delete_token } = await res.json();
    deleteToken = delete_token;
    const token = (url as string).split("/r/")[1];
    const rootId = (await idsByExternalId(request, token)).c_root;

    // An anonymous viewer.
    const context = await browser.newContext();
    const page = await context.newPage();
    await openPlan(page, token);
    await selectInMessageAndPressC(page, card(page, rootId).locator(":scope > .comment-body"), "Members only");
    await expect(page.locator(".subthread-composer")).toHaveCount(0);
    await expect.poll(() => messageQuoteHighlights(page)).toEqual([]);
    await context.close();
  });
});

// ============================================================
// Collapse and resolve at every depth
// ============================================================
//
// A resolved card collapses, unless an open sub-thread sits under it (then it
// stays expanded); unresolving expands it again. The chevron collapses and
// re-expands any card, at any depth, resolved or not, and that choice holds
// until the card changes state: then the new state's default applies.

type Chain = { R: string; S1: string; S2: string; S3: string };

// A root thread on the plan and three nested sub-threads, each on the reply
// of the one above it (depths 0 to 3).
function chainPayload() {
  const root = {
    external_id: "R",
    body: "Root thread body.",
    replies: [{ external_id: "A0", body: "Answer above S1." }],
    file: PLAN.path, start_line: 3, end_line: 3, scope: "line",
  };
  const level = (n: number) =>
    subThread(`S${n}`, `A${n - 1}`, `S${n} body.`, "Answer above", 0,
      n < 3 ? { replies: [{ external_id: `A${n}`, body: `Answer above S${n + 1}.` }] } : {});
  return { comments: [root], sub_threads: [level(1), level(2), level(3)] };
}

async function exerciseCollapse(scope: Locator, chain: Chain) {
  const { R, S1, S2, S3 } = chain;
  const card = (id: string) => scope.locator(`.comment-card[data-comment-id="${id}"]`);
  const chevron = (id: string) => card(id).locator(":scope > .comment-header .comment-collapse-btn").click();
  const expectCollapsed = (id: string) => expect(card(id)).toHaveClass(/(^|\s)collapsed(\s|$)/);
  const expectExpanded = (id: string) => expect(card(id)).not.toHaveClass(/(^|\s)collapsed(\s|$)/);
  // Resolve or Unresolve: the card's own button, then the rebuilt card.
  const toggleResolved = async (id: string, resolved: boolean) => {
    await card(id).locator(":scope > .comment-header .resolve-btn").click();
    if (resolved) await expect(card(id)).toHaveClass(/resolved-card/);
    else await expect(card(id)).not.toHaveClass(/resolved-card/);
  };

  // Resolving the root with sub-threads open under it: it stays expanded,
  // and the chevrons still collapse and re-expand the root and its child.
  await toggleResolved(R, true);
  await expect(card(R).locator("xpath=..")).toHaveClass(/has-open-subthreads/);
  await expectExpanded(R);
  await chevron(R);
  await expectCollapsed(R);
  await expect(card(S1)).toBeHidden();
  await chevron(R);
  await expectExpanded(R);
  await expect(card(S1)).toBeVisible();
  await chevron(S1);
  await expectCollapsed(S1);
  await expect(card(S2)).toBeHidden();
  await chevron(S1);
  await expectExpanded(S1);

  // Depth 1, resolved with open sub-threads under it: same as the root.
  await toggleResolved(S1, true);
  await expectExpanded(S1);
  await chevron(S1);
  await expectCollapsed(S1);
  await chevron(S1);
  await expectExpanded(S1);

  // Depth 3, nothing under it: resolving collapses it; the chevron re-expands
  // and collapses it again.
  await toggleResolved(S3, true);
  await expectCollapsed(S3);
  await chevron(S3);
  await expectExpanded(S3);
  await chevron(S3);
  await expectCollapsed(S3);

  // Depth 2, toggled by hand while open: resolving still collapses it. It was
  // the last open sub-thread under the resolved S1 and root: they collapse
  // too, although the user had re-expanded both with the chevron.
  await chevron(S2);
  await chevron(S2);
  await expectExpanded(S2);
  await toggleResolved(S2, true);
  await expectCollapsed(R);
  await expect(card(R).locator("xpath=..")).not.toHaveClass(/has-open-subthreads/);
  await chevron(R);
  await expectExpanded(R);
  await expectCollapsed(S1);
  await chevron(S1);
  await expectExpanded(S1);
  await expectCollapsed(S2);
  await chevron(S2);
  await expectExpanded(S2);

  // Unresolving the root, collapsed by hand just before, expands it.
  await chevron(R);
  await expectCollapsed(R);
  await toggleResolved(R, false);
  await expectExpanded(R);

  // Unresolving depth 2 expands it, and S1 above it, resolved with an open
  // sub-thread again, takes that state's default: expanded.
  await toggleResolved(S2, false);
  await expectExpanded(S2);
  await expectExpanded(S1);
  await expect(card(S1).locator("xpath=..")).toHaveClass(/has-open-subthreads/);
}

test.describe("Sub-thread collapse and resolve", () => {
  let deleteToken: string | null = null;

  test.afterEach(async ({ request }) => {
    if (deleteToken) await deleteReview(request, deleteToken);
    deleteToken = null;
  });

  test("in a rendered document: resolve, unresolve and chevrons at depths 0 to 3", async ({ page, request }) => {
    const shared = await shareAsOwner(request, page, chainPayload());
    deleteToken = shared.deleteToken;
    await openPlan(page, shared.token);
    const { R, S1, S2, S3 } = shared.ids;
    await exerciseCollapse(page.locator("#document-renderer"), { R, S1, S2, S3 });
  });
});

// ============================================================
// Keep the reader in place
// ============================================================
//
// Collapsing, expanding, resolving or unresolving a card changes its height.
// The page must not move under the reader: the clicked card keeps its place
// in the window, within 3px. A nested card in a thread crossing the top of
// the viewport needs holdCardInView (document-renderer.js), since a resolve
// rebuilds its whole root thread.

const LONG_TEXT = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt. ".repeat(4);

// A long plan, so the window scrolls with a card in the middle of it.
const LONG_PLAN = {
  path: "plan.md",
  content: "# Plan\n\n" + Array.from({ length: 40 }, (_, i) => `Paragraph ${i + 1}. ${LONG_TEXT}`).join("\n\n") + "\n",
};
// Paragraph 30 of LONG_PLAN.
const LONG_PLAN_LINE = 3 + 2 * 29;

type Tall = { R: string; S1: string; S2: string };

/** Wait two animation frames. */
async function nextFrames(page: Page) {
  await page.evaluate(() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(() => r(true)))));
}

/** Wait until the scroll position holds for a few frames. */
async function waitForScrollStable(page: Page) {
  let last = -1;
  let calm = 0;
  for (let i = 0; i < 60 && calm < 3; i++) {
    const now = await page.evaluate(() => window.scrollY);
    calm = Math.abs(now - last) < 0.5 ? calm + 1 : 0;
    last = now;
    await nextFrames(page);
  }
}

function viewportTop(card: Locator): Promise<number> {
  return card.evaluate((el) => el.getBoundingClientRect().top);
}

// Put a card's top 200px below the top of the window.
async function placeCard(page: Page, card: Locator) {
  await expect(card).toBeVisible();
  await expect(async () => {
    await nextFrames(page);
    await waitForScrollStable(page);
    await card.evaluate((el) => window.scrollBy({ top: el.getBoundingClientRect().top - 200, behavior: "instant" }));
    await nextFrames(page);
    await waitForScrollStable(page);
    expect(await page.evaluate(() => window.scrollY), "the window is scrolled").toBeGreaterThan(0);
    expect(Math.abs((await viewportTop(card)) - 200), "the card sits mid-window").toBeLessThanOrEqual(2);
  }).toPass({ timeout: 10_000 });
}

// Run `action` on a card, wait for its effect (`done`), then record how far
// the card moved once the window has settled.
async function cardShift(page: Page, card: Locator, action: () => Promise<void>, done: () => Promise<void>) {
  const before = await viewportTop(card);
  await action();
  await done();
  for (let i = 0; i < 3; i++) await nextFrames(page);
  await waitForScrollStable(page);
  return Math.round(((await viewportTop(card)) - before) * 10) / 10;
}

// crit's exerciseHold: depth 0 (chevron twice, resolve, unresolve), then depth
// 2 (chevron twice, unresolve, resolve, which closes S1 around it).
async function exerciseHold(page: Page, scope: Locator, chain: Tall) {
  const shifts: Record<string, number> = {};
  const card = (id: string) => scope.locator(`.comment-card[data-comment-id="${id}"]`);
  const chevron = (id: string) => () => card(id).locator(":scope > .comment-header .comment-collapse-btn").click();
  const resolveButton = (id: string) => () => card(id).locator(":scope > .comment-header .resolve-btn").click();
  const collapsed = (id: string, yes: boolean) => async () => {
    if (yes) await expect(card(id)).toHaveClass(/(^|\s)collapsed(\s|$)/);
    else await expect(card(id)).not.toHaveClass(/(^|\s)collapsed(\s|$)/);
  };
  const resolved = (id: string, yes: boolean) => async () => {
    if (yes) await expect(card(id)).toHaveClass(/resolved-card/);
    else await expect(card(id)).not.toHaveClass(/resolved-card/);
  };

  // Depth 0: the root, with its (resolved) sub-threads below it.
  await placeCard(page, card(chain.R));
  shifts["depth 0 collapse"] = await cardShift(page, card(chain.R), chevron(chain.R), collapsed(chain.R, true));
  shifts["depth 0 expand"] = await cardShift(page, card(chain.R), chevron(chain.R), collapsed(chain.R, false));
  shifts["depth 0 resolve"] = await cardShift(page, card(chain.R), resolveButton(chain.R), resolved(chain.R, true));
  await expect(card(chain.R)).toHaveClass(/(^|\s)collapsed(\s|$)/);
  shifts["depth 0 unresolve"] = await cardShift(page, card(chain.R), resolveButton(chain.R), resolved(chain.R, false));
  await expect(card(chain.R)).not.toHaveClass(/(^|\s)collapsed(\s|$)/);

  // Depth 2: open S1 (resolved, collapsed) to reach S2, then the same.
  await card(chain.S1).locator(":scope > .comment-header .comment-collapse-btn").click();
  await collapsed(chain.S1, false)();
  await placeCard(page, card(chain.S2));
  shifts["depth 2 expand"] = await cardShift(page, card(chain.S2), chevron(chain.S2), collapsed(chain.S2, false));
  shifts["depth 2 collapse"] = await cardShift(page, card(chain.S2), chevron(chain.S2), collapsed(chain.S2, true));
  shifts["depth 2 unresolve"] = await cardShift(page, card(chain.S2), resolveButton(chain.S2), resolved(chain.S2, false));
  await expect(card(chain.S2)).not.toHaveClass(/(^|\s)collapsed(\s|$)/);
  // Resolving it again closes S1 too (resolved, nothing open under it any
  // more): S2 is hidden in it, and S1 stays where it was.
  shifts["depth 2 resolve (S1 held)"] = await cardShift(page, card(chain.S1), resolveButton(chain.S2), collapsed(chain.S1, true));
  await expect(card(chain.S2)).toHaveClass(/resolved-card/);

  for (const [step, shift] of Object.entries(shifts)) {
    expect(Math.abs(shift), `${step}: the clicked card did not move`).toBeLessThanOrEqual(3);
  }
}

// A root on paragraph 30 of LONG_PLAN, with long messages and two nested
// sub-threads, both resolved, so the root starts as a plain open thread
// (crit's seedTallChain).
function tallChain() {
  const root = {
    external_id: "R",
    body: "Root. " + LONG_TEXT,
    replies: [{ external_id: "A0", body: "Answer. " + LONG_TEXT }],
    file: LONG_PLAN.path, start_line: LONG_PLAN_LINE, end_line: LONG_PLAN_LINE, scope: "line",
  };
  return {
    files: [LONG_PLAN],
    comments: [root],
    sub_threads: [
      subThread("S1", "A0", "S1. " + LONG_TEXT, "Answer", 0, {
        resolved: true,
        replies: [{ external_id: "B1", body: "Sub-thread reply. " + LONG_TEXT }, { external_id: "A1", body: "Answer. " + LONG_TEXT }],
      }),
      subThread("S2", "A1", "S2. " + LONG_TEXT, "Answer", 0, {
        resolved: true,
        replies: [{ external_id: "B2", body: "Sub-thread reply. " + LONG_TEXT }],
      }),
    ],
  };
}

// A resolved root on paragraph 30 of LONG_PLAN with a resolved sub-thread,
// under which only S2 is open: both stay expanded until S2 is resolved, then
// collapse around it.
function settlingChain() {
  const root = {
    external_id: "R",
    body: "Root.",
    resolved: true,
    replies: [{ external_id: "A0", body: "Answer above S1." }],
    file: LONG_PLAN.path, start_line: LONG_PLAN_LINE, end_line: LONG_PLAN_LINE, scope: "line",
  };
  return {
    files: [LONG_PLAN],
    comments: [root],
    sub_threads: [
      subThread("S1", "A0", "S1 body.", "Answer", 0, { resolved: true, replies: [{ external_id: "A1", body: "Answer above S2." }] }),
      subThread("S2", "A1", "S2 body.", "Answer", 0),
    ],
  };
}

test.describe("Sub-threads keep the reader in place", () => {
  let deleteToken: string | null = null;

  test.afterEach(async ({ request }) => {
    if (deleteToken) await deleteReview(request, deleteToken);
    deleteToken = null;
  });

  test("resolving the last open sub-thread under resolved ancestors keeps the outermost in place", async ({ page, request }) => {
    const shared = await shareAsOwner(request, page, settlingChain());
    deleteToken = shared.deleteToken;
    await openPlan(page, shared.token);
    const card = (id: string) => page.locator(`#document-renderer .comment-card[data-comment-id="${id}"]`);
    const { R, S1, S2 } = shared.ids;
    await expect(card(R)).not.toHaveClass(/(^|\s)collapsed(\s|$)/);
    await placeCard(page, card(R));
    const shift = await cardShift(page, card(R), async () => {
      await card(S2).hover();
      await card(S2).locator(":scope > .comment-header .resolve-btn").click();
    }, async () => {
      await expect(card(S1)).toHaveClass(/(^|\s)collapsed(\s|$)/);
      await expect(card(R)).toHaveClass(/(^|\s)collapsed(\s|$)/);
    });
    expect(Math.abs(shift), "the outermost ancestor did not move").toBeLessThanOrEqual(3);
    expect(await page.evaluate(() => window.scrollY), "the page did not jump to the top").toBeGreaterThan(0);
  });

  test("collapsing, expanding and resolving a card at depth 0 and 2 does not move it", async ({ page, request }) => {
    const shared = await shareAsOwner(request, page, tallChain());
    deleteToken = shared.deleteToken;
    await openPlan(page, shared.token);
    const { R, S1, S2 } = shared.ids;
    await exerciseHold(page, page.locator("#document-renderer"), { R, S1, S2 });
  });
});
