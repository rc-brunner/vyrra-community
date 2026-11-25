# Desktop models and interaction design

In the desktop source with the **Models** sidebar item, users can download, import, switch and remove speech models. The catalog has six multilingual Whisper models, four English models and a separate Qwen 2.5 1.5B writing model. Base is the first-install default. The older public installers offer Base under Dictate and Qwen in the writing tools. The catalog belongs to the next desktop release.

## Controls

The default desktop control is 32 × 32 pixels for an icon or 32 pixels high for a labeled button. Use a 16-pixel outline icon, an 8-pixel control radius and a visible 2-pixel focus ring. The 52-pixel model row has a 28-pixel glyph, model name, file size and a right-aligned primary action. Reserve the secondary action’s space even when hidden. On touch, controls grow to 44 pixels and rows to at least 56 pixels. Text can wrap and rows can grow at larger font sizes.

Use the app’s Inter and system sans-serif stack. At the default text size, page headings are 24/30 pixels, model names are 13/18, metadata is 12/16, and keycaps are 11/15. Line heights scale with the text. The catalog fits up to two columns and switches to one when two 17-rem rows would crowd the controls. File sizes use decimal units. Use tabular numerals for transfer progress and elapsed time. Selection has a check and the words “In use” in both themes.

| Interaction | Response |
| --- | --- |
| Hover or keyboard focus | Reveal import or remove beside the main action. Fine pointers get a tooltip after 350 ms. Keyboard focus shows it immediately. Touch exposes the actions directly. |
| Press | Compress only the glyph to 92–94% for 80 ms. Its hit area stays fixed. |
| Hover and state changes | Change color and opacity over 120 ms. Preserve row geometry and focus order. |
| Panel, tooltip and disclosure | The panel fades in and settles by 2 pixels over 160 ms. A disclosure chevron turns in the same time. Text becomes available immediately. |
| Download | The download glyph becomes a spinner inside the same button. Show bytes as a percentage. Import, verification and activation have distinct labels. Keep Cancel beside an active transfer. |
| Completion or failure | Show a check and “In use” only after speech model activation. A failed or canceled replacement preserves the prior active model. Display an actionable error and allow retry. |
| Waveform | Interpolate live input height over 110 ms. The main listening meter follows microphone levels. Only the appearance preview uses a decorative loop. |
| Reduced motion | Keep static controls, focus outlines, progress text and state changes. Remove spins, glyph presses and panel travel. |
| Shortcuts | Show a real shortcut in the control. Find uses the slash key. Dictate and Finish use Command/Control + Enter in the Dictate window. They ignore repeated keys, composition and typing in editors. |

The shared feedback curve is `cubic-bezier(.2,.7,.2,1)`. The press curve is `cubic-bezier(.4,0,.2,1)`. A busy spinner makes one linear turn in 900 ms. The kit is implemented in the desktop stylesheet and uses the existing semantic light, dark, accent and focus colors.

## Model files

**Models → Sources & files** opens the pinned upstream files or the installed models folder. Speech files use the name `ggml-<id>.bin`. Qwen imports a folder containing its Q4_K_M GGUF and `tokenizer.json`. Both writing assets must be present. Installation verifies the file lengths and SHA-256 hashes before activation. Restart restores the last chosen speech model. English-only models accept English speech. English translation requires a multilingual, non-Turbo model.

The catalog and speech engine use the same embedded manifest. Whisper weights are MIT licensed and Qwen 2.5 1.5B Instruct is Apache-2.0 licensed. [Whisper files](https://huggingface.co/ggerganov/whisper.cpp/tree/5359861c739e955e79d9a303bcbc70fb988958b1) · [Qwen weights](https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/tree/91cad51170dc346986eccefdc2dd33a9da36ead9) · [Qwen tokenizer](https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct/blob/989aa7980e4cf806f80c7fef2b1adb7bc71aa306/tokenizer.json)
