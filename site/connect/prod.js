// The consent page's environment (scripts/site.sh deploys it as
// assets/connect-config.js). Firebase web config is public by design: it
// identifies the project, it doesn't authorize anything. The app is
// Terraform's (global stack, the firebase_web_config output).
window.HEART_CONNECT = {
    apiBase: 'https://api.heart-of.me/v1',
    firebase: {
        apiKey: 'AIzaSyDAsAqVagpRJ8d4HoYkH1FfWjOeWo5TPiQ',
        authDomain: 'heart-of.me',
        projectId: 'heart-of-yours',
        appId: '1:340497087616:web:035ff9d0a96454f0b83a65',
    },
};
