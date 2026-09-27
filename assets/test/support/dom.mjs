// The small slice of browser globals the renderer glue touches, for node
// tests. install() returns the fakes so tests can inspect and drive them.

export function install({ protocol = 'http:', cookie = '', theme = null, systemLight = false } = {}) {
  let cookieJar = cookie
  const writes = []
  const store = new Map(theme ? [['phx:theme', theme]] : [])
  const style = { id: 'crit-palette', textContent: '' }
  const attrs = new Map()
  const root = {
    dataset: {}, style: {},
    hasAttribute: name => attrs.has(name),
    getAttribute: name => (attrs.has(name) ? attrs.get(name) : null),
    setAttribute: (name, value) => attrs.set(name, String(value)),
    removeAttribute: name => attrs.delete(name),
  }
  const element = () => ({
    className: '', dataset: {}, style: {}, isConnected: true,
    children: [], remove() { this.isConnected = false },
    appendChild(child) { this.children.push(child); return child },
    querySelector() { return null },
  })
  globalThis.window = globalThis
  globalThis.location = { protocol }
  globalThis.document = {
    body: null,
    documentElement: root,
    get cookie() { return cookieJar },
    set cookie(value) {
      writes.push(value)
      const [pair] = value.split(';')
      const name = pair.slice(0, pair.indexOf('='))
      const rest = cookieJar.split('; ').filter(c => c && !c.startsWith(name + '='))
      cookieJar = rest.concat(pair).join('; ')
    },
    createElement: element,
    getElementById: id => (id === 'crit-palette' ? style : null),
    head: { appendChild() {} },
  }
  globalThis.localStorage = {
    getItem: key => (store.has(key) ? store.get(key) : null),
    setItem: (key, value) => store.set(key, String(value)),
    removeItem: key => store.delete(key),
  }
  globalThis.requestAnimationFrame = fn => fn()
  globalThis.matchMedia = query => ({ matches: query.includes('light') ? systemLight : !systemLight, addEventListener() {} })
  return { writes, root, style, store }
}
