---
title: What Heart is
description: Heart is now in both app stores so I might as well make a declaration post and list some features.
date: 2026-10-19T19:12Z
---

Heart is now in both app stores so I might as well make a declaration post and list some features.

Heart is first of all a hobby project, a child of passion and an exercise in a few things. It started as a coding itch and then I eventually saw that I can "finish" the app - make one that I use myself.

What's wrong with the one I had? Perfectly fine app. What is odd is that features that it hides behind a paywall should definitely be free - my own data.

So, here's the first engineering challenge - how do I design the app that is free for me no matter how many features I pack into it and cheap even if other people decide to use it?

Well, I'm a developer so why don't I test my own skills in cost engineering, on top of everything else, to build something that cares about the user.

A few guiding principles I decided on from the start and have not yet violated:

- The user's data stays with the user. I don't own it, I don't sit on it, it's none of my business. The user can take their data and leave.
- Minimized annoyance. I myself am easily annoyed with bad UX, much more so - by surveillance and intrusiveness of modern software. The app only does what is explicitly allowed and nothing else. I made the app's code public, to back that up.
- A collateral of the above - privacy.
- Free if it costs me nothing but labour. The initial set of features primarily targets what the device can do without cloud involvement and cloud itself is scrupulously optimized. So, the app tests me as dev, among other things.

So here's what I have so far:

- workout logger itself, fully featured, pretty standard industry wide experience with a list of sets that you tap
- exercise library - in my personal opinion, it's really strong, each exercise has a fair bit of metadata that allows the app to offer replacements: if you're protective of your spine, say, the app will hint that hack squat is a suitable alternative to the barbell variant. The library is also easy to search.
- Charts, LOTS OF THEM! And more to come! All your data is yours, as we remember, so go ahead - make charts, look back at your history (I have 5+ years worth that I ported to this app), export it and massage any way you want.
- On that note, two modern features - [API](https://heart-of.me/developers.html) and [MCP](https://heart-of.me/developers.html#mcp). Plug your history into your favourite AI assistant and talk to it about your progress. The feature is free, albeit rate-limited.
- Close feature parity between Android and iOS + iPadOS - the app is built in Flutter so I am taking full advantage of the framework. One notable exception - the Watch app only exists on iOS today.
- Programs, my biggest feature yet. It's new so there will be a separate post about it.
- Tons of platform-specific bells and whistles: Siri, Shortcuts, lock screen widgets, and yes, Apple Watch app.
- Gym selfies! Nuff said.
- One big investment - most features except for the core ones are opt-in. Toggle them off in settings and they will disappear like they were never there.
- Integration with Apple Health and Health Connect on your phones and on your terms.

Full feature list updated every release: on the [web](https://heart-of.me/features.html) or in the app.
