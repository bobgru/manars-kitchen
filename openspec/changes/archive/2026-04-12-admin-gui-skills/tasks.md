# Tasks: Admin GUI — Skills

## Backend: Skill REST extensions

- [x] 1. Add `repoRenameSkill`, `repoListSkillImplications`, `repoRemoveSkillImplication` to Repository record in `Repo/Types.hs`
- [x] 2. Implement `sqlRenameSkill`, `sqlListSkillImplications`, `sqlRemoveSkillImplication` in `Repo/SQLite.hs`; wire into `newSQLiteRepo`
- [x] 3. Add `renameSkill`, `removeSkillImplication`, `listSkillImplications` to `Service/Worker.hs`
- [x] 4. Add JSON types (`RenameSkillReq`, `AddImplicationReq`) to `Server/Json.hs`
- [x] 5. Add 4 endpoint types to `RawAPI` in `Server/Api.hs`
- [x] 6. Add handlers in `Server/Handlers.hs`; wire into `server` function
- [x] 7. Build and fix all warnings

## Frontend: Dashboard shell

- [x] 8. Add `react-router` dependency (`cd web && npm install react-router`)
- [x] 9. Create `Sidebar.tsx` — nav links with active highlighting
- [x] 10. Create `DashboardPage.tsx` — placeholder landing page
- [x] 11. Restructure `App.tsx` — add BrowserRouter and route definitions
- [x] 12. Restructure `AppShell.tsx` — sidebar + content area (outlet + persistent terminal)
- [x] 13. Update `App.css` — sidebar, split layout, content area styles
- [x] 14. Verify terminal persistence across navigation (history and scroll preserved)

## Frontend: Skills pages

- [x] 15. Create `api/skills.ts` — REST client functions
- [x] 16. Create `SkillsListPage.tsx` — table with implication chain display (direct + transitive in parens)
- [x] 17. Create `SkillDetailPage.tsx` — name editing, implication checkboxes, transitive closure display
- [x] 18. Add table/form/checkbox styles to `App.css`

## Integration

- [x] 19. Build frontend (`cd web && npm run build`) and verify with `make server`
- [x] 20. Test full flow: login, navigate to skills, view list, drill into detail, rename, toggle implications, verify transitive closure updates
- [x] 21. Verify terminal still works alongside GUI (type commands, see output)
- [x] 22. Run `stack clean && stack build` and `stack test` — fix all warnings
- [x] 23. Verify demo still works (`make fast-demo`)
