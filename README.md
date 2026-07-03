# Poor Man's Clicky

Poor Man's Clicky is an independent fork of [Clicky](https://github.com/farzaa/clicky) by Farza.

This repository began as a clone of the open-source Clicky codebase.
The goal is to openly preserve attribution while evolving the project into a separate product with its own roadmap, branding, architecture, and commercial direction.

This is not the official Clicky project.
It is not affiliated with Farza, Clicky, OpenAI, Anthropic, or any other AI provider.

## Why this fork exists

The original Clicky project is an AI buddy that lives near your cursor and can help with screen-aware interactions.

Poor Man's Clicky explores a different direction:

- Remove hard dependency on hosted AI API calls.
- Prefer local user-controlled sessions where possible.
- Build a desktop controller that can work with the user's own tools, accounts, browser profiles, or CLI workflows.
- Keep the project hackable, understandable, and product-ready.
- Eventually evolve into a separately branded app that can be packaged, distributed, and sold.

## Attribution

This project is derived from:

- Original project: https://github.com/farzaa/clicky
- Original author: Farza
- Original license: MIT License

The original Clicky license is preserved in this repository.
Any substantial portions of the original Clicky source remain subject to the original MIT License notice.

## License and commercial use

The upstream Clicky project is released under the MIT License.

The MIT License allows use, copying, modification, publishing, distribution, sublicensing, and sale of the software, provided that the original copyright notice and permission notice are included in all copies or substantial portions of the software.

This fork may be developed into a commercial product.
Commercialization does not remove the obligation to preserve the original MIT License notice for code derived from Clicky.

## Product direction

The intended direction for this fork is:

- Local-first desktop control.
- User-owned accounts and sessions.
- No bundled provider API keys.
- No shared or resold access to third-party AI services.
- No hidden credential extraction.
- No bypassing provider limits, restrictions, or terms.
- Clear separation between this project and the services it may help the user control locally.

In other words: this project should become a user-controlled desktop tool, not a proxy for reselling or bypassing access to another company's service.

## Current status

This fork is early-stage.

The codebase still contains inherited Clicky structure, naming, and implementation details.
Part of the roadmap is to gradually replace inherited branding, remove unnecessary API dependencies, simplify the architecture, and turn this into a distinct product.

## Development setup

Open the project in Xcode:

```bash
open leanring-buddy.xcodeproj

