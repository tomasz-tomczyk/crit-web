// Shared keyboard shortcut definitions, persistence, and key normalization.
// Overrides are local to this Crit Web origin and shared by files + preview.

const STORAGE_KEY = "crit-shortcuts"
const FILES = ["files"]
const PREVIEW = ["preview"]
const BOTH = ["files", "preview"]

export const shortcutGroups = [
  { label: "Navigation", shortcuts: [
    { id: "next_block", binding: "j", action: "Next block", modes: FILES },
    { id: "previous_block", binding: "k", action: "Previous block", modes: FILES },
    { id: "visual_mode", binding: "Shift+V", action: "Visual line mode (extend with next/previous block, then comment)", modes: FILES },
    { id: "next_comment", binding: "]", action: "Next comment", modes: FILES },
    { id: "previous_comment", binding: "[", action: "Previous comment", modes: FILES },
  ] },
  { label: "Comments", shortcuts: [
    { id: "comment", binding: "c", action: "Comment on focused block (or text selection, with quote)", modes: FILES },
    { id: "edit_comment", binding: "e", action: "Edit comment on focused block", modes: FILES },
    { id: "delete_comment", binding: "d", action: "Delete comment on focused block", modes: FILES },
    { id: "general_comment", binding: "Shift+G", action: "General comment", modes: FILES },
    { binding: "Ctrl+Enter", action: "Submit the open comment or reply", modes: BOTH, fixed: true },
  ] },
  { label: "Review", shortcuts: [
    { id: "toggle_comments", binding: "Shift+C", action: "Toggle comments panel", modes: FILES },
  ] },
  { label: "Preview", shortcuts: [
    { id: "toggle_pin_mode", binding: "p", action: "Toggle pin mode", modes: PREVIEW },
  ] },
  { label: "View", shortcuts: [
    { id: "toggle_toc", binding: "t", action: "Toggle table of contents", modes: FILES },
    { id: "toggle_resolved", binding: "h", action: "Toggle hide resolved", modes: FILES },
    { binding: "Esc", action: "Cancel / clear focus", modes: BOTH, fixed: true },
    { binding: "?", action: "Toggle this panel", modes: BOTH, fixed: true },
  ] },
]

const byId = new Map()
shortcutGroups.forEach(group => group.shortcuts.forEach(shortcut => {
  if (shortcut.id) byId.set(shortcut.id, shortcut)
}))

function readOverrides() {
  try {
    const value = JSON.parse(localStorage.getItem(STORAGE_KEY) || "{}")
    if (!value || typeof value !== "object" || Array.isArray(value)) return {}
    return Object.fromEntries(Object.entries(value).filter(([id, binding]) => (
      byId.has(id) && typeof binding === "string"
    )))
  } catch (_) {
    return {}
  }
}

function writeOverrides(value) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(value || {}))
}

export function getBinding(id) {
  const shortcut = byId.get(id)
  if (!shortcut) return ""
  const saved = readOverrides()
  return Object.prototype.hasOwnProperty.call(saved, id) ? saved[id] : shortcut.binding
}

export function setBinding(id, binding) {
  const shortcut = byId.get(id)
  if (!shortcut) return false
  const saved = readOverrides()
  if (binding === shortcut.binding) delete saved[id]
  else saved[id] = binding
  writeOverrides(saved)
  return true
}

export function resetAll() {
  writeOverrides({})
}

export function isCustomized(id) {
  return Object.prototype.hasOwnProperty.call(readOverrides(), id)
}

export function eventToBinding(event) {
  let key = event.key
  if (!key || ["Shift", "Control", "Alt", "Meta"].includes(key)) return ""
  const names = { " ": "Space", Escape: "Esc" }
  key = names[key] || key

  const shiftedGlyphs = {
    "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6",
    "&": "7", "*": "8", "(": "9", ")": "0", _: "-", "+": "=",
    "{": "[", "}": "]", ":": ";", '"': "'", "<": ",", ">": ".",
    "?": "/", "|": "\\", "~": "`",
  }
  let shifted = !!event.shiftKey
  if (shiftedGlyphs[key]) {
    key = shiftedGlyphs[key]
    shifted = true
  }

  if (shifted && /^Digit[0-9]$/.test(event.code || "")) key = event.code.slice(5)
  else if (shifted) {
    const codeKeys = {
      BracketLeft: "[", BracketRight: "]", Semicolon: ";", Quote: "'",
      Comma: ",", Period: ".", Slash: "/", Backslash: "\\", Backquote: "`",
      Minus: "-", Equal: "=",
    }
    if (codeKeys[event.code]) key = codeKeys[event.code]
  }
  if (key.length === 1 && /^[a-zA-Z]$/.test(key)) {
    key = shifted ? key.toUpperCase() : key.toLowerCase()
  }

  const parts = []
  if (event.ctrlKey) parts.push("Ctrl")
  if (event.altKey) parts.push("Alt")
  if (shifted) parts.push("Shift")
  if (event.metaKey) parts.push("Meta")
  parts.push(key)
  return parts.join("+")
}

export function actionForEvent(event, mode) {
  const binding = eventToBinding(event)
  if (!binding) return ""
  for (const group of shortcutGroups) {
    for (const shortcut of group.shortcuts) {
      if (shortcut.id && shortcut.modes.includes(mode) && getBinding(shortcut.id) === binding) {
        return shortcut.id
      }
    }
  }
  return ""
}

export function findConflict(id, binding) {
  if (!binding) return null
  const target = byId.get(id)
  if (!target) return null
  for (const group of shortcutGroups) {
    for (const shortcut of group.shortcuts) {
      if (!shortcut.id || shortcut.id === id) continue
      if (!shortcut.modes.some(mode => target.modes.includes(mode))) continue
      if (getBinding(shortcut.id) === binding) return shortcut
    }
  }
  return null
}

export function groupsForMode(mode) {
  return shortcutGroups.map(group => ({
    label: group.label,
    shortcuts: group.shortcuts.filter(shortcut => shortcut.modes.includes(mode)),
  })).filter(group => group.shortcuts.length > 0)
}

export function isReservedBinding(binding) {
  if (["Esc", "Tab", "Enter"].includes(binding)) return true
  const parts = binding.split("+")
  if (parts[parts.length - 1] === "/" && parts.includes("Shift")) return true
  return parts[parts.length - 1] === "Enter" && (parts.includes("Ctrl") || parts.includes("Meta"))
}
