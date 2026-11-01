// An invitation on the web does what it does in the app. Anyone can read who is
// asking and whether the link is good. Answering, or making a link, signs in with
// Firebase as the consent page does, and the API trusts the ID token. With no
// `t` in the address, the page makes a link instead.
import {initializeApp} from 'https://www.gstatic.com/firebasejs/11.0.2/firebase-app.js';
import {
    GoogleAuthProvider,
    OAuthProvider,
    createUserWithEmailAndPassword,
    getAuth,
    onAuthStateChanged,
    signInWithEmailAndPassword,
    signInWithPopup,
    signOut,
} from 'https://www.gstatic.com/firebasejs/11.0.2/firebase-auth.js';

const config = window.HEART_CONNECT;
const token = new URLSearchParams(location.search).get('t');
const $ = (id) => document.getElementById(id);

const show = (state) => {
    for (const section of document.querySelectorAll('main section')) section.hidden = section.id !== `state-${state}`;
};

const message = (title, body) => {
    $('message-title').textContent = title;
    $('message-body').textContent = body;
    show('message');
};

const gone = () => message(
    'This invitation has ended',
    'It has expired, been withdrawn or been answered. Ask the person who sent it for a new one.',
);

function signInInto(container, auth) {
    container.replaceChildren($('sign-in').content.cloneNode(true));
    const error = container.querySelector('[data-error]');
    const failed = (cause) => {
        error.textContent = 'That didn\'t work. Try again, or sign in another way.';
        error.hidden = false;
        console.warn(cause);
    };
    container.querySelector('[data-sign-in=google]').onclick =
        () => signInWithPopup(auth, new GoogleAuthProvider()).catch(failed);
    container.querySelector('[data-sign-in=apple]').onclick =
        () => signInWithPopup(auth, new OAuthProvider('apple.com')).catch(failed);
    const form = container.querySelector('[data-sign-in=email]');
    form.onsubmit = (event) => {
        event.preventDefault();
        signInWithEmailAndPassword(auth, form.email.value, form.password.value).catch(failed);
    };
    container.querySelector('[data-create]').onclick = () => {
        if (form.reportValidity()) createUserWithEmailAndPassword(auth, form.email.value, form.password.value).catch(failed);
    };
}

async function preview() {
    const response = await fetch(`${config.apiBase}/invitation-links/${encodeURIComponent(token)}`);
    return response.ok ? response.json() : null;
}

function start() {
    // Framed inside another page, Accept could be clickjacked; the CDN sends
    // frame-ancestors 'none' too.
    if (window.top !== window.self) {
        return message('Open this page directly', 'It can only be used in its own window.');
    }
    if (!config || !config.firebase) {
        return message('Not available yet', 'Invitations aren\'t switched on here yet.');
    }

    const auth = getAuth(initializeApp(config.firebase));
    const api = async (path, body) => fetch(`${config.apiBase}${path}`, {
        method: 'POST',
        headers: {
            Authorization: `Bearer ${await auth.currentUser.getIdToken()}`,
            'Content-Type': 'application/json',
        },
        body: JSON.stringify(body ?? {}),
    });

    return token ? answering(auth, api) : making(auth, api);
}

async function answering(auth, api) {
    const invitation = await preview().catch(() => null);
    if (!invitation?.good) return gone();

    if (invitation.inviterName) $('inviter-name').textContent = invitation.inviterName;
    if (invitation.inviterAvatar) {
        $('inviter-photo').src = invitation.inviterAvatar;
        $('inviter-photo').hidden = false;
    }
    // this address opens Heart when it's installed, with its fragment, which is
    // how the coach's key reaches a device
    $('open-app').href = location.href;
    $('done-open-app').href = location.href;
    signInInto($('ask-signed-out'), auth);
    $('sign-out').onclick = () => signOut(auth);

    const answer = (path, body, title, text) => async () => {
        for (const id of ['accept', 'decline', 'block']) $(id).disabled = true;
        const response = await api(`/invitation-links/${encodeURIComponent(token)}/${path}`, body);
        if (!response.ok) {
            const {code} = await response.json().catch(() => ({}));
            return code === 'own_invitation'
                ? message('This is your own invitation', 'Send it to the person it\'s for.')
                : gone();
        }
        $('done-title').textContent = title;
        $('done-body').textContent = text;
        show('done');
    };

    $('accept').onclick = () => answer(
        'accept',
        {shares: [...($('share-history').checked ? ['history'] : []), ...($('share-goals').checked ? ['goals'] : [])]},
        'You\'re connected',
        'Open Heart on your phone for your program and your messages. Messages wait until you do.',
    )();
    $('decline').onclick = answer('decline', {}, 'You said no', 'They\'ll see that you declined. Nothing was shared.');
    $('block').onclick = answer('block', {}, 'Blocked', 'They can\'t invite or reach you. Nothing was shared.');

    onAuthStateChanged(auth, (user) => {
        const signedIn = Boolean(user) && !user.isAnonymous;
        $('ask-signed-out').hidden = signedIn;
        $('ask-signed-in').hidden = !signedIn;
        $('signed-in-as').textContent = user?.email || 'your account';
        show('ask');
    });
}

function making(auth, api) {
    signInInto($('make-signed-out'), auth);

    $('make-form').onsubmit = async (event) => {
        event.preventDefault();
        const response = await api('/invitations', {name: $('invitee-name').value});
        if (response.status === 403) {
            return message('Coaching is open to testers for now', 'Get in touch if you\'d like to try it.');
        }
        if (!response.ok) return message('Something went wrong', 'You may have too many open invitations.');
        const invitation = await response.json();
        $('made-link').value = `${location.origin}${location.pathname}?t=${encodeURIComponent(invitation.token)}`;
        show('link');
    };

    onAuthStateChanged(auth, (user) => {
        const signedIn = Boolean(user) && !user.isAnonymous;
        $('make-signed-out').hidden = signedIn;
        $('make-form').hidden = !signedIn;
        show('make');
    });
}

start();
