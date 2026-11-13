// Draws one scene (lua/flora/pdfout.lua M.scene) with flora's web
// renderers, as the mixer draws a page: ?scene=URL of its JSON, scale=
// device pixels per bp, mode=webgl (the default) or canvas2d. Sets
// window.drawn to the renderer used once the canvas holds the picture
// (site/tools/band-probe.mjs reads it).
import { fromPdfScene, WebGLRenderer, drawCanvas2D } from "@alpaca-software/web-flora";

const q = new URLSearchParams(location.search);
const scene = await (await fetch(q.get("scene"))).json();
const scale = Number(q.get("scale") || 1);
const canvas = document.getElementById("c");
canvas.width = Math.round(scene.width * scale);
canvas.height = Math.round(scene.height * scale);
const list = fromPdfScene(scene);
if (q.get("mode") === "canvas2d") {
  drawCanvas2D(canvas.getContext("2d"), list, { scale, y0: 0 });
  window.drawn = "canvas2d";
} else {
  const off = new OffscreenCanvas(canvas.width, canvas.height);
  new WebGLRenderer(off).draw(list, { scale, y0: 0 });
  canvas.getContext("2d").drawImage(off.transferToImageBitmap(), 0, 0);
  window.drawn = "webgl";
}
