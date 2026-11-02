// Signed out, this page reads who is asking and whether the link is good. The
// answer happens in the app, which this same address opens when it's installed.
const show = (id) => {
    for (const section of document.querySelectorAll('main section')) section.hidden = section.id !== id;
};

const token = new URLSearchParams(location.search).get('t');

async function preview() {
    if (!token) return null;
    const response = await fetch(`${window.HEART_CONNECT.apiBase}/invitation-links/${encodeURIComponent(token)}`);
    return response.ok ? response.json() : null;
}

const invitation = await preview().catch(() => null);

if (invitation?.good) {
    if (invitation.inviterName) document.getElementById('inviter-name').textContent = invitation.inviterName;
    if (invitation.inviterAvatar) {
        const photo = document.getElementById('inviter-photo');
        photo.src = invitation.inviterAvatar;
        photo.hidden = false;
    }
    document.getElementById('open-app').href = location.href;
    show('state-ask');
} else {
    show('state-gone');
}
