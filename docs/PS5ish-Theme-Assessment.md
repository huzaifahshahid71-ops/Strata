# PS5ish theme assessment

The supplied PS5-Custom-Theme.zip contains PS5ish version 5.0.3 by David Griggs, targeting Playnite Fullscreen Theme API 2.3.0. It is a Windows WPF/XAML theme, not an iOS theme package. The files were inspected as reference material; they were not executed.

It can be recreated as Strata's Cinematic presentation using SwiftUI. Loading its XAML, Windows solution or Playnite controls directly into LiveContainer is not supported by the current app architecture.

| Theme component | Adaptation to Strata |
| --- | --- |
| Top navigation and search/settings/profile region | Native SwiftUI controls wired to the existing library, categories, search and interface actions. |
| Horizontal game rail and selected-cover enlargement | Existing guest registry, independent Cinematic cover artwork, controller selection and native animations. The theme defines 1.06× hover/focus and a 1.5× single-row focus variant, with 75–200 ms focus animations. |
| Full-screen backgrounds and overlays | Existing mode-specific backgrounds with native crossfades and safe-area-aware content. |
| Play button and contextual actions | Existing LiveContainer launch handler plus saved button size and position. |
| Playnite-specific store, SuccessStory trophies, notifications and profile data | Use real Strata-supported destinations or omit unavailable data. Do not display invented progress or accounts. |
| Audio files | The archive includes navigation.wav, activation.wav and background.mp3. A native sound option is feasible; Strata already has an optional original navigation cue. |

GlobalResources.xaml uses a 1920×1080 design canvas. Copying these desktop coordinates literally would reintroduce clipping on a landscape iPhone. A port should preserve proportions while adapting the rail, header and launch area to the actual iPhone/iPad viewport and safe areas.

This turn evaluates the theme. The implemented changes in revision 13 concern Home page management and widgets; Cinematic has not been replaced with a PS5ish port.
