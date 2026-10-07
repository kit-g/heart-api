// The OAuth consent page: an app (Claude, ChatGPT, …) asked to read this
// account's training log, and the account answers here. The page signs the
// account in with Firebase, as the app does, then reads, approves or denies
// the request through the API with that session. It holds no secret: the API
// trusts the Firebase ID token, and the browser follows the redirect it gets
// back.
import {initializeApp} from 'https://www.gstatic.com/firebasejs/11.0.2/firebase-app.js';
import {
    GoogleAuthProvider,
    OAuthProvider,
    getAuth,
    onAuthStateChanged,
    signInWithEmailAndPassword,
    signInWithPopup,
    signOut,
} from 'https://www.gstatic.com/firebasejs/11.0.2/firebase-auth.js';

const config = window.HEART_CONNECT;
const requestId = new URLSearchParams(window.location.search).get('request');
const $ = (id) => document.getElementById(id);

function show(state) {
    for (const section of ['loading', 'sign-in', 'consent', 'message']) {
        $(`state-${section}`).hidden = section !== state;
    }
}

function message(title, body) {
    $('message-title').textContent = title;
    $('message-body').textContent = body;
    show('message');
}

function start() {
    // Framed inside another page, Allow could be clickjacked; the CDN sends
    // frame-ancestors 'none' too, this is the belt to those braces.
    if (window.top !== window.self) {
        return message('Open this page directly', 'It can only be used in its own window.');
    }
    if (!requestId) {
        return message('Nothing to connect', 'Start connecting from the app you want to use with Heart.');
    }
    if (!config || !config.firebase) {
        return message('Not available yet', 'Connecting apps to Heart isn\'t switched on here yet.');
    }

    const auth = getAuth(initializeApp(config.firebase));
    const api = (path, init = {}) => auth.currentUser.getIdToken().then((token) => fetch(
        `${config.apiBase}/oauth/requests/${encodeURIComponent(requestId)}${path}`,
        {...init, headers: {...(init.headers || {}), Authorization: `Bearer ${token}`}},
    ));

    const signInError = (error) => {
        $('sign-in-error').textContent = 'That didn\'t work. Try again, or sign in another way.';
        $('sign-in-error').hidden = false;
        console.warn(error);
    };
    $('sign-in-google').onclick = () => signInWithPopup(auth, new GoogleAuthProvider()).catch(signInError);
    $('sign-in-apple').onclick = () => signInWithPopup(auth, new OAuthProvider('apple.com')).catch(signInError);
    $('sign-in-email').onsubmit = (event) => {
        event.preventDefault();
        signInWithEmailAndPassword(auth, $('email').value, $('password').value).catch(signInError);
    };
    $('sign-out').onclick = () => signOut(auth);

    const answer = (path) => async () => {
        $('allow').disabled = $('deny').disabled = true;
        const response = await api(path, {method: 'POST'});
        if (!response.ok) {
            return message('This request is no longer open', 'Go back to the app and start connecting again.');
        }
        const {redirect} = await response.json();
        const to = new URL(redirect);
        if (to.protocol !== 'https:' && to.protocol !== 'http:') {
            return message('Something went wrong', 'Go back to the app and start connecting again.');
        }
        window.location.assign(to.toString());
    };
    $('allow').onclick = answer('/approve');
    $('deny').onclick = answer('/deny');

    onAuthStateChanged(auth, async (user) => {
        if (!user || user.isAnonymous) {
            if (user) await signOut(auth);
            return show('sign-in');
        }
        show('loading');
        const response = await api('');
        if (response.status === 404) {
            return message('This request is no longer open', 'It expired or was already answered. Go back to the app and start connecting again.');
        }
        if (!response.ok) {
            return message('Something went wrong', 'Try again in a moment, or start connecting again from the app.');
        }
        const request = await response.json();
        $('client-name').textContent = request.client.name;
        $('redirect-host').textContent = request.redirectHost;
        $('surface').textContent = request.resource === 'mcp' ? 'Heart\'s MCP server' : 'Heart\'s API';
        $('signed-in-as').textContent = user.email || 'your account';
        show('consent');
    });
}

start();
