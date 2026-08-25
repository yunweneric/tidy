// Custom bootstrap, so the HTML curtain in index.html is only lifted once
// Flutter has actually painted a frame. The two placeholders are filled in by
// the build — see WebTemplatedFiles in flutter_tools.
//
// Service worker settings are deliberately omitted: a marketing page should
// never serve a cached previous version after a deploy, and there is nothing
// here worth having offline.
{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine();
    await appRunner.runApp();

    // Two frames: one for Flutter to lay out, one for it to paint. Lifting on
    // the first leaves a blank canvas showing for a beat.
    requestAnimationFrame(function () {
      requestAnimationFrame(function () {
        const boot = document.getElementById('boot');
        if (!boot) {
          return;
        }
        boot.classList.add('done');
        setTimeout(function () { boot.remove(); }, 400);
      });
    });
  }
});
