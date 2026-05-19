# Security Policy

## Supported Versions

Stacker is a personal, best-effort open-source project. Only the most recent release receives any security or maintenance attention.

## Reporting a Vulnerability

Stacker is a **local-only macOS desktop utility**. It:

- Never connects to the internet
- Never transmits user data, window contents, or any information
- Does not require accounts, logins, or cloud services

To provide its core functionality (discovering, aligning, focusing, and switching between browser windows), Stacker requests two macOS permissions:

- **Accessibility** (`Privacy_Accessibility` in System Settings > Privacy & Security): Allows the app to inspect, move, resize, focus, and observe windows belonging to supported browsers (Chrome, Brave, Safari, Edge, Firefox). This is the primary mechanism.
- **Automation / Apple Events** (`com.apple.security.automation.apple-events`): Used as a fallback via System Events when Accessibility does not expose sufficient window data for a particular browser or state. You will see a one-time macOS Automation prompt the first time this path is needed.

These permissions are strictly local. Stacker can only act on windows *on the machine where it is running*. It cannot be used remotely, and no capability is ever sent over the network.

### How to report security issues

If you find a vulnerability in Stacker (for example, a flaw in permission handling, build artifacts, or release signing that could be abused locally), please report it responsibly rather than filing a public issue:

- Open a private security advisory on the GitHub repository (preferred), **or**
- Email the maintainer directly

We will acknowledge and investigate reports on a best-effort basis. Because this is a personal tool maintained in spare time, response times are not guaranteed.

Thank you for practicing responsible disclosure and for helping keep Stacker safe and trustworthy for its users.
