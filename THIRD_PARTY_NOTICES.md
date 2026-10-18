# Third-party notices

The neon app icon and white transparent menu bar icon were supplied by the project owner for suya-unduck. Their inclusion does not grant a separate license to these artwork files.

Core Audio helper, atomic shared-state, render, gain, and tap lifecycle code was adapted from the user-supplied technical specification, with additional validation and implementation work. The specification described the process-tap approach used by [Unduck-Pro](https://github.com/MrRockySL/Unduck-Pro) by MrRockySL (MIT), including the experimental device-property mechanism. The enabled refresh/replay approach was adapted after inspecting commit 5dcdd670c64a6fbbc2e5cb2f57c1611005ebd856. No private-function lookup, unsafe realtime object access, or unity hard clipping from that reference was copied; no GPL code was used. Attribution is retained here for the architectural reference.

Apple Core Audio, AppKit, SwiftUI, ServiceManagement and the Swift standard library are system dependencies, governed by their respective licenses. No third-party packages are downloaded or bundled.

## Unduck-Pro license

MIT License

Copyright (c) 2026 MrRockySL

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
