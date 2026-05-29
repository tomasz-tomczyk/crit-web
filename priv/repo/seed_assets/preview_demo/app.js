// Trivial interaction to prove JS executes inside the preview iframe:
// clicking the CTA increments a running count of "deploys watched".
(function () {
  "use strict";

  var cta = document.getElementById("cta");
  if (!cta) return;

  var count = 0;

  cta.addEventListener("click", function () {
    count += 1;
    cta.textContent = "Start free — " + count + " deploys watched";
  });
})();
