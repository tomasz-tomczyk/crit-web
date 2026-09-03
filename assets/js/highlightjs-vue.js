/*
Language: Vue.js
Requires: xml.js, javascript.js, typescript.js, css.js, stylus.js, scss.js
Author: Sara Lissette Luis Ibáñez <lissette.ibnz@gmail.com>
Description: Single-File Components of Vue.js Framework

Shim for highlightjs-vue@1.0.0. The published package's CJS build writes
module$1.exports (unusable) and its .esm.js file is CommonJS, so esbuild
cannot import a language function from the package directly. Keep this in
sync with node_modules/highlightjs-vue/dist/highlightjs-vue.esm.js when
bumping the dependency.
*/
export function vue(hljs) {
  return {
    name: "Vue",
    aliases: ["vue"],
    subLanguage: "xml",
    contains: [
      hljs.COMMENT("<!--", "-->", {
        relevance: 10,
      }),
      {
        begin: /^(\s*)(<script>)/gm,
        end: /^(\s*)(<\/script>)/gm,
        subLanguage: "javascript",
        excludeBegin: true,
        excludeEnd: true,
      },
      {
        begin: /^(\s*)(<script lang=["']ts["']>)/gm,
        end: /^(\s*)(<\/script>)/gm,
        subLanguage: "typescript",
        excludeBegin: true,
        excludeEnd: true,
      },
      {
        begin: /^(\s*)(<style(\sscoped)?>)/gm,
        end: /^(\s*)(<\/style>)/gm,
        subLanguage: "css",
        excludeBegin: true,
        excludeEnd: true,
      },
      {
        begin: /^(\s*)(<style lang=["'](scss|sass)["'](\sscoped)?>)/gm,
        end: /^(\s*)(<\/style>)/gm,
        subLanguage: "scss",
        excludeBegin: true,
        excludeEnd: true,
      },
      {
        begin: /^(\s*)(<style lang=["']stylus["'](\sscoped)?>)/gm,
        end: /^(\s*)(<\/style>)/gm,
        subLanguage: "stylus",
        excludeBegin: true,
        excludeEnd: true,
      },
    ],
  };
}
