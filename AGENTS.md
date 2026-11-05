<!-- LOVABLE:BEGIN -->
> [!IMPORTANT]
> This project is connected to [Lovable](https://lovable.dev). Avoid rewriting
> published git history — force pushing, or rebasing/amending/squashing commits
> that are already pushed — as it rewrites history on Lovable's side and the
> user will likely lose their project history.
>
> Commits you push to the connected branch sync back to Lovable and show up in
> the editor, so keep the branch in a working state.
<!-- LOVABLE:END -->

- The hosted checkout script owns merchant popup dimensions; embedded checkout CSS owns internal fitting and scrolling so merchants do not duplicate or restyle the payment UI.
- Keep the splash logo inline using the supplied artwork data so it needs no separate image request; preserve the checkout's existing sizing and animation styles.
