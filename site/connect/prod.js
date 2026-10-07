// The consent page's environment (scripts/site.sh deploys it as
// assets/connect-config.js). Prod has no Firebase web app registered yet, so
// the page says connecting isn't available; registering one fills `firebase`
// in the shape dev.js uses.
window.HEART_CONNECT = {
    apiBase: 'https://api.heart-of.me/v1',
    firebase: null,
};
