/* Auto Upi popup checkout. Usage:
 *   <script src="https://autoupi.in/checkout.js"></script>
 *   AutoUpi.open({ url: "<payment_url from create-order>", onSuccess, onFailure, onClose });
 * The popup message is for updating your page only. Always trust the
 * server-to-server webhook (or order-status API) before delivering goods.
 */
(function () {
  if (window.AutoUpi) return;
  var current = document.currentScript && document.currentScript.src;
  var ORIGIN = current ? new URL(current).origin : "https://autoupi.in";

  function open(opts) {
    opts = opts || {};
    if (!opts.url) throw new Error("AutoUpi.open: url is required");
    var target = new URL(opts.url, ORIGIN);
    if (target.origin !== ORIGIN || !/^\/pay\/[a-z0-9]+$/.test(target.pathname)) {
      throw new Error("AutoUpi.open: url must be an Auto Upi payment link");
    }
    target.searchParams.set("embed", "1");

    var overlay = document.createElement("div");
    overlay.setAttribute("style", "position:fixed;inset:0;z-index:2147483647;background:rgba(15,10,30,.6);display:flex;align-items:center;justify-content:center;opacity:0;transition:opacity .25s ease");
    var box = document.createElement("div");
    var mobile = window.matchMedia("(max-width:760px)").matches;
    box.setAttribute("style", mobile
      ? "--autoupi-popup-border:rgba(0,0,0,.22);position:relative;box-sizing:border-box;width:94vw;height:80vh;height:80dvh;border:3px solid var(--autoupi-popup-border);border-radius:10px;overflow:hidden;background:#fff"
      : "--autoupi-popup-border:rgba(0,0,0,.22);position:relative;box-sizing:border-box;width:min(860px,94vw);height:min(520px,80vh);border:3px solid var(--autoupi-popup-border);border-radius:10px;overflow:hidden;background:#fff;box-shadow:0 30px 80px rgba(0,0,0,.35);transform:translateY(16px);transition:transform .3s ease");
    var frame = document.createElement("iframe");
    frame.src = target.toString();
    frame.title = "Auto Upi checkout";
    frame.setAttribute("allow", "clipboard-write");
    frame.setAttribute("style", "border:0;width:100%;height:100%;display:block");
    var close = document.createElement("button");
    close.type = "button";
    close.setAttribute("aria-label", "Close payment");
    close.textContent = "\u00d7";
    close.setAttribute("style", "position:absolute;top:8px;right:10px;z-index:2;width:34px;height:34px;border:0;border-radius:50%;background:rgba(0,0,0,.08);font-size:22px;line-height:34px;cursor:pointer;color:#222");

    var done = false;
    function cleanup() {
      window.removeEventListener("message", onMessage);
      document.body.style.overflow = prevOverflow;
      overlay.style.opacity = "0";
      setTimeout(function () { overlay.remove(); }, 250);
    }
    function onMessage(ev) {
      if (ev.origin !== ORIGIN || ev.source !== frame.contentWindow || !ev.data) return;
      var d = ev.data;
      if (d.type !== "autoupi:paid" && d.type !== "autoupi:failed") return;
      if (done) return;
      done = true;
      cleanup();
      var result = { order_id: d.order_id, status: d.type === "autoupi:paid" ? "paid" : "failed" };
      var cb = d.type === "autoupi:paid" ? opts.onSuccess : opts.onFailure;
      if (typeof cb === "function") cb(result);
    }
    close.onclick = function () {
      if (done) return;
      done = true;
      cleanup();
      if (typeof opts.onClose === "function") opts.onClose();
    };

    var prevOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    window.addEventListener("message", onMessage);
    box.appendChild(frame);
    box.appendChild(close);
    overlay.appendChild(box);
    document.body.appendChild(overlay);
    requestAnimationFrame(function () {
      overlay.style.opacity = "1";
      box.style.transform = "none";
    });
  }

  window.AutoUpi = { open: open };
})();
