{{flutter_js}}
{{flutter_build_config}}

// No service worker. Flutter's default one kept a copy of the app on the
// phone, so after a deploy Safari went on showing the previous version
// (seen on 25 Nov). The app needs the network anyway (Firebase), and the
// browser's normal cache, revalidated on every visit (firebase.json), keeps
// loading fast. index.html also removes a worker left from before.
_flutter.loader.load();
