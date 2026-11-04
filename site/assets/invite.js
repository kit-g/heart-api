// An invitation on the web does what it does in the app. Anyone can read who is
// asking and whether the link is good. Answering, or making a link, signs in with
// Firebase as the consent page does, and the API trusts the ID token. With no
// `t` in the address, the page makes a link instead.
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

const unreachable = () => message(
    'Heart can\'t be reached right now',
    'Your invitation is fine. Check your connection and open this link again in a moment.',
);

const failed = (element, text) => {
    element.textContent = text;
    element.hidden = false;
};

// Firebase loads only once the page needs a sign-in, so reading who is asking
// works even where its scripts can't be fetched.
async function firebase() {
    const [app, auth] = await Promise.all([
        import('https://www.gstatic.com/firebasejs/11.0.2/firebase-app.js'),
        import('https://www.gstatic.com/firebasejs/11.0.2/firebase-auth.js'),
    ]);
    return {...auth, auth: auth.getAuth(app.initializeApp(config.firebase))};
}

function signInInto(container, fb) {
    container.replaceChildren($('sign-in').content.cloneNode(true));
    const error = container.querySelector('[data-error]');
    const signInFailed = (cause) => {
        failed(error, 'That didn\'t work. Try again, or sign in another way.');
        console.warn(cause);
    };
    container.querySelector('[data-sign-in=google]').onclick =
        () => fb.signInWithPopup(fb.auth, new fb.GoogleAuthProvider()).catch(signInFailed);
    container.querySelector('[data-sign-in=apple]').onclick =
        () => fb.signInWithPopup(fb.auth, new fb.OAuthProvider('apple.com')).catch(signInFailed);
    const form = container.querySelector('[data-sign-in=email]');
    form.onsubmit = (event) => {
        event.preventDefault();
        fb.signInWithEmailAndPassword(fb.auth, form.email.value, form.password.value).catch(signInFailed);
    };
    container.querySelector('[data-create]').onclick = () => {
        if (form.reportValidity()) {
            fb.createUserWithEmailAndPassword(fb.auth, form.email.value, form.password.value).catch(signInFailed);
        }
    };
}

// Whoever signs in or out, nothing typed for the last person stays on the page.
function clearSignIn() {
    for (const form of document.querySelectorAll('[data-sign-in=email]')) form.reset();
    for (const error of document.querySelectorAll('[data-error]')) error.hidden = true;
}

const signedIn = (user) => Boolean(user) && !user.isAnonymous;

function caller(fb) {
    return async (path, body) => fetch(`${config.apiBase}${path}`, {
        method: 'POST',
        headers: {
            Authorization: `Bearer ${await fb.auth.currentUser.getIdToken()}`,
            'Content-Type': 'application/json',
        },
        body: JSON.stringify(body ?? {}),
    });
}

// The link as the API sees it: null when there is no such link, and a throw when
// the answer didn't come, which says nothing about the link.
async function preview() {
    const response = await fetch(`${config.apiBase}/invitation-links/${encodeURIComponent(token)}`);
    if (response.status === 404) return null;
    if (!response.ok) throw new Error(`preview answered ${response.status}`);
    return response.json();
}

async function start() {
    // Framed inside another page, Accept could be clickjacked; the CDN sends
    // frame-ancestors 'none' too.
    if (window.top !== window.self) {
        return message('Open this page directly', 'It can only be used in its own window.');
    }
    if (!config || !config.firebase) {
        return message('Not available yet', 'Invitations aren\'t switched on here yet.');
    }
    if (token === null) return making();
    if (token === '') return gone();
    return answering();
}

async function answering() {
    let invitation;
    try {
        invitation = await preview();
    } catch (cause) {
        console.warn(cause);
        return unreachable();
    }
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
    show('ask');

    let fb;
    try {
        fb = await firebase();
    } catch (cause) {
        console.warn(cause);
        return failed($('ask-error'), 'Signing in isn\'t available here right now. You can answer in the app.');
    }
    const api = caller(fb);
    signInInto($('ask-signed-out'), fb);
    $('sign-out').onclick = () => fb.signOut(fb.auth);

    const buttons = ['accept', 'decline', 'block'].map($);
    const answer = (path, body, title, text) => async () => {
        for (const button of buttons) button.disabled = true;
        $('ask-error').hidden = true;
        try {
            const response = await api(`/invitation-links/${encodeURIComponent(token)}/${path}`, body);
            if (response.ok) {
                $('done-title').textContent = title;
                $('done-body').textContent = text;
                return show('done');
            }
            const {code} = await response.json().catch(() => ({}));
            if (code === 'own_invitation') {
                return message('This is your own invitation', 'Send it to the person it\'s for.');
            }
            if (response.status === 404 || code === 'invitation_gone') return gone();
            failed($('ask-error'), 'That didn\'t go through. Try again in a moment.');
        } catch (cause) {
            console.warn(cause);
            failed($('ask-error'), 'That didn\'t go through. Check your connection and try again.');
        }
        for (const button of buttons) button.disabled = false;
    };

    $('accept').onclick = () => answer(
        'accept',
        {shares: [...($('share-history').checked ? ['history'] : []), ...($('share-goals').checked ? ['goals'] : [])]},
        'You\'re connected',
        'Open Heart on your phone for your program and your messages. Messages wait until you do.',
    )();
    $('decline').onclick = answer('decline', {}, 'You said no', 'They\'ll see that you declined.');
    const block = answer(
        'block',
        {},
        'Blocked',
        'They can\'t invite or reach you, and anything you shared with them has stopped.',
    );
    $('block').onclick = () => {
        if (confirm('Block this person? They won\'t be able to invite or reach you.')) block();
    };

    fb.onAuthStateChanged(fb.auth, (user) => {
        clearSignIn();
        $('ask-signed-out').hidden = signedIn(user);
        $('ask-signed-in').hidden = !signedIn(user);
        $('signed-in-as').textContent = user?.email || 'your account';
    });
}

async function making() {
    let fb;
    try {
        fb = await firebase();
    } catch (cause) {
        console.warn(cause);
        return unreachable();
    }
    const api = caller(fb);
    signInInto($('make-signed-out'), fb);
    $('make-sign-out').onclick = () => fb.signOut(fb.auth);
    show('make');

    const submit = $('make-form').querySelector('[type=submit]');
    $('make-form').onsubmit = async (event) => {
        event.preventDefault();
        submit.disabled = true;
        $('make-error').hidden = true;
        try {
            const response = await api('/invitations', {name: $('invitee-name').value});
            if (response.ok) {
                const invitation = await response.json();
                $('made-link').value = `${location.origin}${location.pathname}?t=${encodeURIComponent(invitation.token)}`;
                return show('link');
            }
            const {code} = await response.json().catch(() => ({}));
            if (code === 'coaching_beta') {
                return message('Coaching is open to testers for now', 'Get in touch if you\'d like to try it.');
            }
            failed($('make-error'), code === 'invitation_limit'
                ? 'You have too many open or recently declined invitations. Withdraw one, or wait a while.'
                : 'That didn\'t go through. Try again in a moment.');
        } catch (cause) {
            console.warn(cause);
            failed($('make-error'), 'That didn\'t go through. Check your connection and try again.');
        }
        submit.disabled = false;
    };

    fb.onAuthStateChanged(fb.auth, (user) => {
        clearSignIn();
        $('make-signed-out').hidden = signedIn(user);
        $('make-form').hidden = !signedIn(user);
        $('make-signed-in-as').textContent = user?.email || 'your account';
    });
}

start();
