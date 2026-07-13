const DEFAULT_ERROR_MESSAGE = "We couldn't confirm whether your change was saved. Reconnect and check the review before trying again."

// LiveView's hook.pushEvent returns a promise when no callback is supplied.
// Always settle that promise here so transport timeouts never escape as
// unhandled rejections. Callers receive an explicit result and can keep their
// optimistic UI (forms, editors, disabled buttons) in a retryable state.
export async function pushMutation(hook, event, payload, options = {}) {
  try {
    const reply = await hook.pushEvent(event, payload)
    if (reply?.ok === false) {
      const error = new Error(reply.error || DEFAULT_ERROR_MESSAGE)
      if (options.onError) options.onError(error)
      return { ok: false, error, reply }
    }
    if (options.onSuccess) options.onSuccess(reply)
    return { ok: true, reply }
  } catch (error) {
    if (options.onError) options.onError(error)
    return { ok: false, error }
  }
}

export function mutationErrorMessage() {
  return DEFAULT_ERROR_MESSAGE
}
