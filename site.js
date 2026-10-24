(function () {
  "use strict";
  var hexGrid = document.querySelector(".hex-grid");
  var legend = document.querySelectorAll(".byte-legend button");
  var selected = "";
  function highlight(kind) { hexGrid.dataset.highlight = kind; }
  legend.forEach(function (button) {
    button.addEventListener("mouseenter", function () { highlight(button.dataset.kind); });
    button.addEventListener("mouseleave", function () { highlight(selected); });
    button.addEventListener("focus", function () { highlight(button.dataset.kind); });
    button.addEventListener("blur", function () { highlight(selected); });
    button.addEventListener("click", function () {
      selected = selected === button.dataset.kind ? "" : button.dataset.kind;
      legend.forEach(function (item) { item.setAttribute("aria-pressed", String(item.dataset.kind === selected)); });
      highlight(selected);
    });
  });
  document.querySelectorAll("[data-copy]").forEach(function (button) {
    button.addEventListener("click", async function () {
      var label = button.textContent;
      try {
        await navigator.clipboard.writeText(button.dataset.copy);
        button.textContent = "Copied";
      } catch (error) {
        button.textContent = "Select the commands above to copy";
      }
      setTimeout(function () { button.textContent = label; }, 2500);
    });
  });
})();
