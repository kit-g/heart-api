// The consent page's environment (scripts/site.sh deploys it as
// assets/connect-config.js). Firebase web config is public by design: it
// identifies the project, it doesn't authorize anything.
window.HEART_CONNECT = {
    apiBase: 'https://api.dev.heart-of.me/v1',
    firebase: {
        apiKey: 'AIzaSyA9lEMg6g5AGXG7zTxmR6ycdshKzLblkjQ',
        authDomain: 'dev.heart-of.me',
        projectId: 'heart-of-yours-dev',
        appId: '1:547445170683:web:93d9ecd705fe873f2e6b5e',
    },
};
