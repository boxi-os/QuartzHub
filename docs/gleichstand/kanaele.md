# Gleichstand: IPC-Kanäle von QuartzControl 1.3

Quelle der Kanäle: `QuartzControl/shared/ipc-contract.ts` (`export const IPC`, 180 Einträge), Handler in
`QuartzControl/electron/main/ipc/handlers.ts` (Menü-Ereignisse in `electron/main/menu.ts`). QC-Dienste liegen
unter `electron/main/services/`. QuartzHub-Kern relativ zu `Packages/QuartzHubCore/Sources/QuartzHubCore/`,
App relativ zum Repo. Stand: Commit 5b11af1, nur gelesen, nichts gebaut oder gestartet.

Status: `da` = Kern und App-Aufruf gefunden · `nur Kern` = Kern ohne App-Aufruf · `anders` = absichtlich
anders gelöst · `fehlt` = nichts gefunden.

## project / appUpdate / templatePackage (Start)

| Kanal | QC | QuartzHub Kern | App | Stand |
|---|---|---|---|---|
| `project:list` | `projectStore.ts:listProjects` | `Projects/ProjectStore.swift` `ProjectStore.list()` (gelesen über `ProjectOverviews.read`) | `App/Projects/ProjectsModel.swift:44`, `App/Pages/Server/DiscoveredServersSection.swift:158` | da |
| `project:overview` | `projectOverviewService.ts:getProjectOverviews` | `Projects/ProjectOverview.swift:52` `ProjectOverviews.read` | `App/Projects/ProjectsModel.swift:44` | da |
| `project:add` | `projectPaths.ts:repointAuthoredFrames` + `projectStore.ts:addProject` | `Projects/ProjectList.swift:21` `ProjectList.add` | `App/Projects/ProjectsModel.swift:54`, `App/Projects/ProjectsWindow.swift:198` | da |
| `project:relocate` | `projectPaths.ts:repointProjectPaths` + `projectStore.ts:relocateProject` | `Projects/ProjectList.swift:30` `ProjectList.relocate` | `App/Projects/ProjectsModel.swift:62`, `App/Projects/ProjectInspector.swift:81` | da |
| `project:open` | `projectStore.ts:touchProject`/`getProject` | `Projects/ProjectList.swift:49` `ProjectList.open` | `App/Projects/ProjectsModel.swift:73` (aus `ProjectsWindow.swift:172`) | da |
| `project:remove` | `buildService.stopServer` + `projectStore.removeProject` + `connectionsService.deleteRelaySecrets` | `Projects/ProjectList.swift:57` `ProjectList.remove` | `App/Projects/ProjectsModel.swift:67` (aus `ProjectsWindow.swift:92`) | da |
| `project:create` | `createService.ts:createProject` + `addProject` | `Projects/ProjectCreation.swift:47` `ProjectCreation.run` (→ `ProjectCreator.create`) | `App/Projects/CreateProjectSheet.swift:208` | da |
| `project:duplicate` | `duplicateService.ts:duplicateProject` + `addProject` | `Projects/ProjectList.swift:39` `ProjectList.duplicate` (→ `ProjectDuplicator.duplicate`) | `App/Projects/DuplicateProjectSheet.swift:121` | da |
| `project:missingDependencies` | `projectDependencies.ts:missingDependencies`/`missingAuthoredFrames` + `pluginService.isInstallingFromLock` | `Projects/ProjectDependencies.swift:14/81`, `Plugins/PluginCommands.swift:100` `isInstallingFromLock` | `App/Pages/Overview/OverviewModel.swift:112-118` | da |
| `appUpdate:check` | `appUpdateService.ts:checkAppUpdate` | `AppUpdateCheck.check` | `ProjectsModel.checkAppUpdate` | anders (2026-11-13: GitHubs `releases/latest` statt `latest.json`) |
| `templatePackage:builtin` | `builtinTemplateService.ts:getBuiltinTemplate` | `Templates/BuiltinTemplate.swift:118` `BuiltinTemplate.find` | `App/Projects/CreateProjectSheet.swift:51`, `App/Pages/Templates/TemplatesModel.swift:172` | da |

## projectIcon

| Kanal | QC | QuartzHub Kern | App | Stand |
|---|---|---|---|---|
| `projectIcon:get` | `projectIconService.ts:getProjectIcon` | `Projects/ProjectIcon.swift:65` `ProjectIcon.info` | `App/Pages/Config/ProjectImageSection.swift:260`, `App/Pages/Plugins/ExtraContentFiles.swift:82` | da |
| `projectIcon:set` | `projectIconService.ts:setProjectIcon` | `Projects/ProjectIcon.swift:119` `ProjectIcon.set` | `App/Pages/Config/ProjectImageSection.swift:39` | da |
| `projectIcon:clear` | `projectIconService.ts:clearProjectIcon` | `Projects/ProjectIcon.swift:140` `ProjectIcon.clear` | `App/Pages/Config/ProjectImageSection.swift:44` | da |
| `projectIcon:setDark` | `projectIconService.ts:setProjectIconDark` | `Projects/ProjectIcon.swift:158` `ProjectIcon.setDark` | `App/Pages/Config/ProjectImageSection.swift:123` | da |
| `projectIcon:clearDark` | `projectIconService.ts:clearProjectIconDark` | `Projects/ProjectIcon.swift:166` `ProjectIcon.clearDark` | `App/Pages/Config/ProjectImageSection.swift:128` | da |

## snippets / staticImage / staticFiles

| Kanal | QC | QuartzHub Kern | App | Stand |
|---|---|---|---|---|
| `snippets:list` | `snippetService.ts:listSnippets` | `Styles/Snippets.swift:116` `Snippets.listSnippets` | `App/Components/OptionsForm/SnippetFields.swift:242`, `App/Pages/Plugins/ExtraContentFiles.swift:77` | da |
| `snippets:read` | `snippetService.ts:readSnippet` | `Styles/Snippets.swift:121` `readSnippet` | `App/Components/OptionsForm/SnippetFields.swift:407`, `App/Pages/Plugins/ExtraContentTab.swift:372` | da |
| `snippets:write` | `snippetService.ts:writeSnippet` | `Styles/Snippets.swift:169` `writeSnippet` | `App/Components/OptionsForm/SnippetFields.swift:273`, `App/Pages/Plugins/ExtraContentFiles.swift:153` | da |
| `snippets:import` | `snippetService.ts:importSnippet` | `Styles/Snippets.swift:210` `importSnippet` | `App/Components/OptionsForm/SnippetFields.swift:293`, `App/Pages/Plugins/ExtraContentFiles.swift:141` | da |
| `staticImage:import` | `snippetService.ts:importStaticImage` | `Styles/Snippets.swift:217` `importImage` | `App/Components/OptionsForm/SnippetFields.swift:72`, `App/Pages/Plugins/ExtraContentFiles.swift:169` | da |
| `staticImage:readSvg` | `snippetService.ts:readSvgSource` | `Styles/Snippets.swift:226` `Snippets.svgSource` (+ `Styles/InlineSvg.swift:191` `clean`) | `App/Components/OptionsForm/SnippetFields.swift:52` | da |
| `staticFiles:listImages` | `snippetService.ts:listStaticImages` | `Styles/Snippets.swift:119` `listImages` | `App/Pages/Plugins/ExtraContentFiles.swift:82` | da |
| `staticFiles:rename` | `snippetService.ts:renameStaticFile` | `Styles/Snippets.swift:252` `rename` | `App/Pages/Plugins/ExtraContentFiles.swift:191` | da |
| `staticFiles:trash` | `snippetService.ts:trashStaticFile` | `Styles/Snippets.swift:263` `moveToTrash` | `App/Pages/Plugins/ExtraContentFiles.swift:220` | da |

## config

| Kanal | QC | QuartzHub Kern | App | Stand |
|---|---|---|---|---|
| `config:get` | `configService.ts:readConfig` | `Config/ConfigFile.swift:45` `ConfigFile.read` | `App/Pages/Config/ConfigModel.swift:31`, `App/Shell/ServerLifecycle.swift:52` | da |
| `config:save` | `configService.ts:writeConfig` | `Config/ConfigFile.swift:112` `ConfigFile.write` | `App/Pages/Config/ConfigModel.swift:50`, `App/Pages/Plugins/PluginsModel.swift:157` | da |

## plugin / forms / theme

| Kanal | QC | QuartzHub Kern | App | Stand |
|---|---|---|---|---|
| `plugin:add` | `pluginService.ts:addPlugin` | `Plugins/PluginCommands.swift:38` `PluginCommands.add` | `App/Pages/Plugins/PluginsModel.swift:289`, `App/Pages/Plugins/MarketplaceTab.swift:46` | da |
| `plugin:remove` | `pluginService.ts:removePlugin` | `Plugins/PluginCommands.swift:44` `remove` | `App/Pages/Plugins/PluginsModel.swift:271` | da |
| `plugin:optionSchema` | `pluginSchemaService.ts:getPluginOptionSchema` | `Plugins/PluginSchemaReader.swift:61` `optionSchema` | `App/Pages/Plugins/PluginInspector.swift:176`, `App/Pages/Plugins/ExtraContentTab.swift:324` | da |
| `forms:check` | `formsService.ts:check` | `Publishing/Forms/FormsCLI.swift:116` `FormsCLI.check` | `App/Pages/Plugins/FormsTab.swift:475` | da |
| `forms:texts` | `formsService.ts:texts` | `Publishing/Forms/FormsCLI.swift:138` `texts` | `App/Pages/Plugins/FormsSections.swift:241` | da |
| `forms:inspectKey` | `formsService.ts:inspectKey` | `Publishing/Forms/FormsCLI.swift:172` `inspectKey` | `App/Pages/Plugins/FormsSections.swift:189` | da |
| `forms:importKey` | `formsService.ts:importKeyFile` | `Publishing/Forms/FormsCLI.swift:185` `FormsCLI.importKeyFile` | `App/Pages/Plugins/FormsSections.swift:170` | da |
| `forms:relayState` | `formsService.ts:relayState` | `Publishing/Forms/FormsRelay.swift:275` `FormsRelay.state` | `App/Pages/Plugins/FormsTab.swift:460` | da |
| `forms:relaySaveSettings` | `formsService.ts:saveRelaySettings` | `Publishing/Forms/FormsRelay.swift:123` `saveSettings` | `App/Pages/Plugins/FormsRelaySection.swift:498` | da |
| `forms:relaySaveSecrets` | `connectionsService.ts:saveRelaySecrets` | `Publishing/Connections.swift:450` `Connections.saveRelaySecrets` | `App/Pages/Plugins/FormInspector.swift:194`, `:533` | da |
| `forms:relayUpload` | `formsService.ts:relayUpload` | `Publishing/Forms/FormsRelay.swift:314` `upload` | `App/Pages/Plugins/FormsRelaySection.swift:565` | da |
| `forms:relayExport` | `formsService.ts:relayExport` | `Publishing/Forms/FormsRelay.swift:385` `export(to:)` | `App/Pages/Plugins/FormsRelaySection.swift:581` | da |
| `forms:relayRemove` | `formsService.ts:relayRemove` | `Publishing/Forms/FormsRelay.swift:406` `remove` | `App/Pages/Plugins/FormsRelaySection.swift:595` | da |
| `forms:relayExcludeFromSite` | `formsService.ts:excludeFromSite` | `Publishing/Forms/FormsRelay.swift:456` `excludeFromSite` | `App/Pages/Plugins/FormsRelaySection.swift:544` | da |
| `plugin:themeStyleSettingsInfo` | `pluginSchemaService.ts:getThemeStyleSettingsInfo` | `Plugins/PluginSchemaReader.swift:361` `themeStyleSettings` | `App/Pages/Styles/ThemeTab.swift:176` | da |
| `themeMarketplace:list` | `themeMarketplaceService.ts:listThemes` | `Themes/ThemeMarketplace.swift:117` `list` | `App/Pages/Styles/ThemeTab.swift:350` | da |
| `themeMarketplace:install` | `themeMarketplaceService.ts:installTheme` | `Themes/ThemeMarketplace.swift:169` `install` | `App/Pages/Styles/ThemeTab.swift:406`, `:278` | da |
| `themeMarketplace:detail` | `themeMarketplaceService.ts:getThemeDetail` | `Themes/ThemeMarketplace.swift:144` `detail` | `App/Pages/Styles/ThemeTab.swift:396` | da |
| `themeMarketplace:styleSettingsSchema` | `styleSettingsSchemaService.ts:getStyleSettingsSchema` | `Themes/StyleSettingsSchema.swift:172` `schema(themeId:)` | `App/Pages/Styles/ThemeTab.swift:182` | da |
| `themeMarketplace:refreshStyleSettingsSchema` | `styleSettingsSchemaService.ts:clearStyleSettingsSchemaCache` + `getStyleSettingsSchema` | `Themes/StyleSettingsSchema.swift:224` `clearCache(themeId:)` + `schema` | `App/Pages/Styles/ThemeTab.swift:192-193` | da |
| `themeMarketplace:refresh` | `themeMarketplaceService.ts:invalidateCache` | `Themes/ThemeMarketplace.swift:136` `invalidate` | `App/Pages/Styles/ThemeTab.swift:309` | da |
| `themePreset:list` | `themePresetsService.ts:listPresets` | `Themes/ThemePresets.swift:7` `ThemePresets.list` | `App/Pages/Styles/ThemeTab.swift:272` | da |
| `themePreset:save` | `themePresetsService.ts:savePreset` | `Themes/ThemePresets.swift:12` `save` | `App/Pages/Styles/ThemeTab.swift:162` | da |
| `themePreset:delete` | `themePresetsService.ts:deletePreset` | `Themes/ThemePresets.swift:18` `delete` | `App/Pages/Styles/ThemeTab.swift:290` | da |
| `plugin:installFromLock` | `pluginService.ts:installFromLock` | `Plugins/PluginCommands.swift:82` `installFromLock` | `App/Pages/Plugins/PluginsModel.swift:314`, `App/Pages/Overview/OverviewModel.swift:170` | da |
| `plugin:prune` | `pluginService.ts:prunePlugins` | `Plugins/PluginCommands.swift:61` `prune` | `App/Pages/Plugins/PluginsModel.swift:315` | da |

## layoutFrame

| Kanal | QC | QuartzHub Kern | App | Stand |
|---|---|---|---|---|
| `layoutFrame:list` | `layoutFrameService.ts:listFrames` | `Layout/LayoutFrames.swift:126` `LayoutFrames.listFrames` | `App/Pages/Layout/LayoutModel.swift:90`, `App/Pages/Plugins/PluginsModel.swift:102` | da |
| `layoutFrame:save` | `layoutFrameService.ts:saveFrame` | `Layout/LayoutFrames.swift:252` `saveFrame` | `App/Pages/Layout/LayoutModel.swift:209` | da |
| `layoutFrame:delete` | `layoutFrameService.ts:deleteFrame` | `Layout/LayoutFrames.swift:266` `deleteFrame` | `App/Pages/Layout/LayoutModel.swift:235`, `App/Pages/Plugins/PluginsModel.swift:266` | da |
| `layoutFrame:builtinPageTypeFrames` | `pluginSchemaService.ts:discoverBuiltinPageTypeFrames` | `Plugins/PluginSchemaReader.swift:280` `pageTypeFrames` | `App/Pages/Layout/LayoutModel.swift:104` | da |
| `layoutFrame:getBreakpoints` | `layoutFrameService.ts:getBreakpointWidths` | `Layout/LayoutFrames.swift:104` `LayoutFrames.widths` | `App/Pages/Layout/LayoutModel.swift:83`, `App/Components/EditorPreview.swift:221` | da |
| `layoutFrame:saveBreakpoints` | `layoutFrameService.ts:saveBreakpointWidths` | `Layout/LayoutFrames.swift:110` `saveWidths` | `App/Pages/Layout/LayoutModel.swift:251` | da |
| `layoutFrame:quartzMeasures` | `styleService.ts:readQuartzFrameMeasures` | `Styles/ScssCheck.swift:152` `ScssCheck.frameMeasures` | `App/Pages/Layout/LayoutModel.swift:86` | da |

## styles

| Kanal | QC | QuartzHub Kern | App | Stand |
|---|---|---|---|---|
| `styles:get` | `styleService.ts:readCustomScss` | `Styles/StyleSheets.swift:63` `StyleSheets.readCustom` | `App/Pages/Styles/StylesModel.swift:88` | da |
| `styles:save` | `styleService.ts:saveCustomScss` | `Styles/StyleSheets.swift:104` `saveCustom` | `App/Pages/Styles/StylesModel.swift:248` | da |
| `styles:reference` | `styleService.ts:getStyleReferences` | `Styles/StyleFiles.swift:171` `StyleFiles.references` | `App/Pages/Styles/StylesPage.swift:132` | da |
| `styles:importFile` | `styleService.ts:importStyleFile` | `Styles/StyleFiles.swift:148` `importFile` | `App/Pages/Styles/CssTab.swift:370` | da |
| `styles:listFiles` | `styleService.ts:listStyleFiles` | `Styles/StyleFiles.swift:58` `list` | `App/Pages/Styles/StylesModel.swift:99`, `App/Pages/Overview/OverviewModel.swift:72` | da |
| `styles:readFile` | `styleService.ts:readStyleFile` | `Styles/StyleFiles.swift:74` `read` | `App/Pages/Styles/CssTab.swift:143` | da |
| `styles:saveFile` | `styleService.ts:writeStyleFile` | `Styles/StyleFiles.swift:80` `write` | `App/Pages/Styles/StylesModel.swift:254`, `App/Pages/Styles/BasicsTab.swift:345` | da |
| `styles:createFile` | `styleService.ts:createStyleFile` | `Styles/StyleFiles.swift:102` `create` | `App/Pages/Styles/CssTab.swift:482`, `App/Pages/Styles/BasicsTab.swift:344` | da |
| `styles:renameFile` | `styleService.ts:renameStyleFile` | `Styles/StyleFiles.swift:119` `rename` | `App/Pages/Styles/CssTab.swift:442` | da |
| `styles:deleteFile` | `styleService.ts:deleteStyleFile` | `Styles/StyleFiles.swift:138` `delete` | `App/Pages/Styles/CssTab.swift:520` | da |
| `styles:setImportOrder` | `styleService.ts:setImportOrder` | `Styles/StyleSheets.swift:328` `setImportOrder` | `App/Pages/Styles/CssTab.swift:359`, `App/Pages/Styles/StylesPage.swift:150` | da |
| `styles:check` | `styleService.ts:checkStyles` | `Styles/ScssCheck.swift:91` `ScssCheck.check` | `App/Pages/Styles/StylesPage.swift:123`, `App/Pages/Overview/OverviewModel.swift:64` | da |
| `styles:checkSource` | `styleService.ts:checkStyleSource` | `Styles/ScssCheck.swift:109` `checkSource` | `App/Pages/Styles/CssTab.swift:164` | da |
| `styles:fontFaces` | `styleService.ts:collectFontFaces` | `Styles/SiteFonts.swift:71` `SiteFonts.faces` | `App/Pages/Styles/BasicsTab.swift:539`, `App/Pages/Styles/CssReference.swift:275` | da |
| `styles:previewFonts` | `styleService.ts:readPreviewFonts` | `Styles/SiteFonts.swift:106` `previewFonts` | `App/Pages/Styles/CssReference.swift:275`, `App/Pages/Styles/BasicsTab.swift:539` | da |
| `styles:getVariableOverrides` | `styleService.ts:getVariableOverrides` | `Styles/StyleSheets.swift:350` `variableOverrides` | `App/Pages/Styles/StylesModel.swift:100` | da |
| `styles:variableCollisions` | `styleService.ts:variableCollisions` | `Styles/StyleSheets.swift:354` `variableCollisions` | `App/Pages/Styles/VariablesTab.swift:99` | da |
| `styles:takenClasses` | `styleService.ts:takenClasses` | `Styles/SiteFonts.swift:130` `takenClasses` | `App/Pages/Plugins/PluginsPage.swift:130`, `App/Pages/Layout/LayoutModel.swift:84` | da |
| `styles:migrate` | `styleService.ts:migrateManagedStyles` | `Styles/StyleSheets.swift:250` `migrate` | `App/Pages/Styles/StylesModel.swift:346` | da |
| `styles:consolidate` | `styleService.ts:consolidateStylesheets` | `Styles/StyleFiles.swift:226` `consolidate` | `App/Pages/Styles/CssTab.swift:197` | da |
| `styles:saveVariableOverrides` | `styleService.ts:saveVariableOverrides` | `Styles/StyleSheets.swift:359` `saveVariableOverrides` | `App/Pages/Styles/StylesModel.swift:267` | da |
| `styles:variableGraph` | `variableGraphService.ts:getVariableGraph` | `Styles/VariableGraph.swift:181` `VariableGraph.graph` | `App/Pages/Styles/StylesModel.swift:117` | da |

## fonts

| Kanal | QC | QuartzHub Kern | App | Stand |
|---|---|---|---|---|
| `fonts:importFile` | `fontService.ts:importFontFile` | `Styles/FontService.swift:95` `importFontFile` | `App/Pages/Styles/BasicsTab.swift:399` | da |
| `fonts:unusedImported` | `fontService.ts:unusedImportedFonts` | `Styles/FontService.swift:177` `unusedImportedFonts` | `App/Pages/Styles/BasicsTab.swift:547` | da |
| `fonts:removeImported` | `fontService.ts:removeImportedFont` | `Styles/FontService.swift:224` `removeImportedFont` | `App/Pages/Styles/BasicsTab.swift:466` | da |
| `fonts:fetchGoogle` | `fontService.ts:fetchGoogleFonts` | `Styles/FontService.swift:383` `fetchGoogleFonts` | `App/Pages/Styles/StylesModel.swift:310` | da |
| `fonts:dropGoogle` | `fontService.ts:dropGoogleFonts` | `Styles/FontService.swift:600` `dropGoogleFonts` | `App/Pages/Styles/StylesModel.swift:331` | da |

## localization

| Kanal | QC | QuartzHub Kern | App | Stand |
|---|---|---|---|---|
| `localization:list` | `localizationService.ts:listLocales` | `Templates/LocaleFiles.swift:69` `LocaleFiles.list` | `App/Pages/Config/LocalizationTab.swift:178` | da |
| `localization:getEntries` | `localizationService.ts:getLocaleEntries` | `Templates/LocaleFiles.swift:108` `entries` | `App/Pages/Config/LocalizationTab.swift:204` | da |
| `localization:saveEntry` | `localizationService.ts:saveLocaleEntry` | `Templates/LocaleFiles.swift:118` `save` | `App/Pages/Config/LocalizationTab.swift:240` | da |
| `localization:gitAttributesStatus` | `localizationService.ts:getGitAttributesStatus` | `Templates/LocaleFiles.swift:206` `gitAttributesActive` | `App/Pages/Config/LocalizationTab.swift:190` | da |
| `localization:ensureGitAttributes` | `localizationService.ts:ensureGitAttributes` | `Templates/LocaleFiles.swift:214` `ensureGitAttributes` | `App/Pages/Config/LocalizationTab.swift:261` | da |

## update / snapshot

| Kanal | QC | QuartzHub Kern | App | Stand |
|---|---|---|---|---|
| `update:coreStatus` | `updateService.ts:getCoreUpdateStatus` | `Updates/CoreUpdate.swift:105` `CoreUpdate.status` | `App/Pages/Updates/UpdatesModel.swift:81`, `App/Pages/Overview/OverviewModel.swift:90` | da |
| `update:coreRun` | `updateService.ts:runCoreUpdate` | `Updates/CoreUpdate.swift:178` `run` | `App/Pages/Updates/UpdatesModel.swift:100` | da |
| `update:coreAbort` | `updateService.ts:abortCoreMerge` | `Updates/CoreUpdate+Abort.swift:5` `abort` | `App/Pages/Updates/UpdatesModel.swift:120`, `App/Pages/GitSync/GitSyncModel.swift:131` | da |
| `update:pluginsStatus` | `updateService.ts:getPluginsUpdateStatus` | `Updates/PluginUpdates.swift:33` `PluginUpdates.status` | `App/Pages/Updates/UpdatesModel.swift:82`, `App/Pages/Plugins/PluginsModel.swift:112` | da |
| `update:pluginRun` | `updateService.ts:updatePlugin` | `Updates/PluginUpdates.swift:97` `PluginUpdates.update` | `App/Pages/Updates/UpdatesModel.swift:146` | da |
| `snapshot:list` | `snapshotService.ts:migrateConfigBackups` + `listSnapshots` | `Snapshots/SnapshotStore.swift:350` `list` (+ `SnapshotStore+Restore.swift:170` `migrateConfigBackups`) | `App/Pages/Snapshots/SnapshotsModel.swift:79-80` | da |
| `snapshot:create` | `snapshotService.ts:createSnapshot` | `Snapshots/SnapshotStore.swift:301` `create` | `App/Pages/Snapshots/SnapshotsModel.swift:139`, `App/Pages/Overview/OverviewModel.swift:190` | da |
| `snapshot:diff` | `snapshotService.ts:diffSnapshot` | `Snapshots/SnapshotStore+Restore.swift:7` `diff` | `App/Pages/Snapshots/SnapshotsModel.swift:106` | da |
| `snapshot:fileDiff` | `snapshotService.ts:fileDiff` | `Snapshots/SnapshotStore+Restore.swift:41` `fileDiff` | `App/Pages/Snapshots/SnapshotsModel.swift:119` | da |
| `snapshot:restore` | `snapshotService.ts:restoreSnapshot` | `Snapshots/SnapshotStore+Restore.swift:57` `restore` | `App/Pages/Snapshots/SnapshotsModel.swift:161` | da |
| `snapshot:delete` | `snapshotService.ts:deleteSnapshot` | `Snapshots/SnapshotStore+Restore.swift:145` `delete` | `App/Pages/Snapshots/SnapshotsModel.swift:183` | da |
| `snapshot:export` | Speicherdialog + `snapshotService.ts:exportSnapshot` | `Snapshots/SnapshotStore+Restore.swift:155` `export` | `App/Pages/Snapshots/SnapshotsModel.swift:194` (NSSavePanel), `:201` | da |
| `snapshot:settings` | `snapshotService.ts:getSettings` | `Snapshots/SnapshotStore.swift:261` `settings` | `App/Pages/Snapshots/SnapshotsModel.swift:85` | da |
| `snapshot:saveSettings` | `snapshotService.ts:saveSettings` | `Snapshots/SnapshotStore.swift:282` `saveSettings` | `App/Pages/Snapshots/SnapshotsModel.swift:213` | da |

## connections

| Kanal | QC | QuartzHub Kern | App | Stand |
|---|---|---|---|---|
| `connections:list` | `connectionsService.ts:listConnections` | `Publishing/Connections.swift:261` `list` | `App/Settings/ConnectionsSettings.swift:199`, `App/Pages/Publish/PublishModel.swift:93` | da |
| `connections:save` | `connectionsService.ts:saveConnection` | `Publishing/Connections.swift:268` `save` | `App/Components/ConnectionForm.swift:289`, `App/Settings/ConnectionsSettings.swift:234` | da |
| `connections:delete` | `connectionsService.ts:deleteConnection` | `Publishing/Connections.swift:338` `delete` | `App/Settings/ConnectionsSettings.swift:264`, `:247` | da |
| `connections:usage` | handler: `projectStore.listProjects` × `publishTargetsService.targetsUsingConnection` | `Publishing/PublishTargets.swift:180` `using(connection:)` (ohne App-Aufruf) | `App/Settings/ConnectionsSettings.swift:200-208` (zählt selbst über `ProjectStore.list` + `PublishTargets.list`) | da (Zählung in der App statt über `using`) |
| `connections:forgetHostKey` | `connectionsService.ts:forgetHostKey` | `Publishing/Connections.swift:378` `forgetHostKey` | `App/Settings/ConnectionsSettings.swift:274` | da |

## github

| Kanal | QC | QuartzHub Kern | App | Stand |
|---|---|---|---|---|
| `github:viewer` | `githubService.ts:getViewer` | `Publishing/GitHubAPI.swift:125` `viewer` | `App/Settings/ConnectionsSettings.swift:224`, `App/Pages/GitSync/GitSyncModel.swift:151` | da |
| `github:originRepo` | `githubService.ts:getOriginRepo` | `Publishing/GitHubAPI.swift:135` `originRepo` | `App/Pages/GitSync/GitSyncModel.swift:92` | da |
| `github:createRepo` | `githubService.ts:createRepo` | `Publishing/GitHubAPI.swift:144` `createRepo` | `App/Pages/GitSync/GitSyncModel.swift:159` | da |
| `github:pagesInfo` | `githubService.ts:getPagesInfo` | `Publishing/GitHubAPI.swift:162` `pagesInfo` | `App/Pages/Publish/GitHubPagesSection.swift:99` | da |
| `github:configurePages` | `githubService.ts:configurePages` | `Publishing/GitHubAPI.swift:178` `configurePages` | `App/Pages/Publish/GitHubPagesSection.swift:117` | da |

## publishTargets

| Kanal | QC | QuartzHub Kern | App | Stand |
|---|---|---|---|---|
| `publishTargets:list` | `publishTargetsService.ts:listTargets` | `Publishing/PublishTargets.swift:120` `list` | `App/Pages/Publish/PublishModel.swift:97`, `App/Pages/Overview/OverviewModel.swift:73` | da |
| `publishTargets:save` | `publishTargetsService.ts:saveTarget` | `Publishing/PublishTargets.swift:143` `save` | `App/Pages/Publish/TargetSheet.swift:403` | da |
| `publishTargets:delete` | `publishTargetsService.ts:deleteTarget` | `Publishing/PublishTargets.swift:173` `delete` | `App/Pages/Publish/PublishModel.swift:304` | da |

## books

| Kanal | QC | QuartzHub Kern | App | Stand |
|---|---|---|---|---|
| `books:list` | `bookService.ts:listBooks` | `Export/Books.swift:307` `Books.list` | `App/Pages/Documents/DocumentsModel.swift:149` | da |
| `books:read` | `bookService.ts:readBook` | `Export/Books.swift:319` `Books.read` (Aufrufer nur `Publishing/DocumentAdapter.swift:52`) | — (die Seite nimmt die Bücher aus `Books.list`) | nur Kern (QC-Renderer ruft `books.read` ebenfalls nirgends auf) |
| `books:save` | `bookService.ts:saveBook` | `Export/Books.swift:328` `save` | `App/Pages/Documents/DocumentsModel.swift:204`, `:184` | da |
| `books:delete` | `bookService.ts:deleteBook` | `Export/Books.swift:359` `delete` | `App/Pages/Documents/DocumentsModel.swift:240` | da |
| `books:sitePages` | `export/exportService.ts:readSitePages` | `Export/ExportBook.swift:236` `ExportBook.sitePages` | `App/Pages/Documents/DocumentsModel.swift:279` | da |

## deploy / export / dialog (Dateiauswahl)

| Kanal | QC | QuartzHub Kern | App | Stand |
|---|---|---|---|---|
| `deploy:diff` | `deploy/index.ts:previewDeploy` | `Publishing/Deploy.swift:120` `Deploy.preview` | `App/Pages/Publish/PublishModel.swift:161` | da |
| `deploy:run` | `deploy/index.ts:runDeploy` | `Publishing/Deploy.swift:138` `Deploy.run` | `App/Pages/Publish/PublishModel.swift:275` | da |
| `deploy:forgetManifest` | `deploy/manifest.ts:forgetManifest` | `Publishing/DeployManifests.swift:61` `forget` | `App/Pages/Publish/PublishModel.swift:198` | da |
| `export:cancel` | `export/exportService.ts:cancelExport` | `Export/ExportBook.swift:34` `ExportBook.cancel` | `App/Pages/Publish/PublishModel.swift:291` | da |
| `deploy:progress` (Ereignis) | `deployService.deployEvents` → `broadcast` | `progress`-Closure von `Deploy` | `App/Shell/AppDeploy.swift:32`, `App/Pages/Publish/PublishModel.swift:147` | anders (Closure statt Ereigniskanal) |
| `dialog:pickFile` | `showOpenDialog({openFile})` | — (App-Sache) | `App/Components/Confirm.swift:56` `FilePick.one`, z. B. `App/Pages/Plugins/FormsSections.swift:164`; `App/Components/ConnectionForm.swift:217` | anders (NSOpenPanel in der App) |
| `dialog:openPath` | `shell.openPath` (nur innerhalb registrierter Projekte) | — (App-Sache) | `App/Pages/Styles/CssTab.swift:132`, `App/Pages/Server/BuildServerPage.swift:247`, `App/Pages/Overview/OverviewPage.swift:414` | anders (NSWorkspace.open direkt) |

## templatePackage

| Kanal | QC | QuartzHub Kern | App | Stand |
|---|---|---|---|---|
| `templatePackage:export` | Speicherdialog + `templatePackage:exportPackage` | `Templates/TemplatePackage.swift:154` `export` | `App/Pages/Templates/TemplatesModel.swift:128` (NSSavePanel), `:141` | da |
| `templatePackage:inspect` | `templatePackage:inspectProject` | `Templates/TemplatePackage.swift:141` `inspect` | `App/Pages/Templates/TemplatesModel.swift:106` | da |
| `templatePackage:pick` | `showOpenDialog` (Datei oder Ordner) | — (App-Sache) | `App/Pages/Templates/TemplatesModel.swift:155` `pick` (NSOpenPanel) | anders (NSOpenPanel in der App) |
| `templatePackage:plan` | `templatePackage:planImport` | `Templates/TemplatePackage.swift:281` `plan` | `App/Pages/Templates/TemplatesModel.swift:200`, `:215` | da |
| `templatePackage:import` | `templatePackage:importPackage` | `Templates/TemplatePackage.swift:303` `importPackage` | `App/Pages/Templates/TemplatesModel.swift:267` | da |
| `templatePackage:progress` (Ereignis) | Callback von `importPackage` → `broadcast` | Closure von `importPackage` | `App/Pages/Templates/TemplatesModel.swift:267` | anders (Closure statt Ereigniskanal) |

## marketplace

| Kanal | QC | QuartzHub Kern | App | Stand |
|---|---|---|---|---|
| `marketplace:list` | `marketplaceService.ts:listPlugins` | `Plugins/Marketplace.swift:97` `list` | `App/Pages/Plugins/MarketplaceTab.swift:24` | da |
| `marketplace:refresh` | `marketplaceService.ts:invalidateCache` | `Plugins/Marketplace.swift:111` `invalidate` | `App/Pages/Plugins/MarketplaceTab.swift:32` | da |
| `marketplace:readme` | `marketplaceService.ts:readme` | `Plugins/Marketplace.swift:164` `readme` | `App/Pages/Plugins/MarketplaceTab.swift:253` | da |

## server / sitePreview

| Kanal | QC | QuartzHub Kern | App | Stand |
|---|---|---|---|---|
| `server:start` | `buildService.ts:startServer` | `Build/BuildService.swift:338` `startServer` | `App/Pages/Server/BuildServerModel.swift:92`, `App/Components/EditorPreview.swift:229` | da |
| `server:stop` | `buildService.ts:stopServer` | `Build/BuildService.swift:430` `stopServer` | `App/Pages/Server/BuildServerModel.swift:97`, `App/Components/EditorPreview.swift:236` | da |
| `server:restart` | `buildService.ts:restartServer` | `Build/BuildService.swift:450` `restartServer` | `App/Pages/Server/BuildServerModel.swift:102`, `App/Pages/Overview/OverviewModel.swift:142` | da |
| `server:status` | `buildService.ts:getServerStatus` | `Build/BuildService.swift:290` `serverStatus` | `App/Shell/BuildMonitor.swift:66` (gelesen von `BuildServerPage.swift:23`, `OverviewPage.swift:22`) | da |
| `server:statusChanged` (Ereignis) | `serverEvents 'status'` → `broadcast` | `BuildService.Event.status` über `onEvent` | `App/Shell/ServerLifecycle.swift:24-30` (AsyncStream) → `App/Shell/BuildMonitor.swift:30` | anders (AsyncStream in den `BuildMonitor`) |
| `server:log` (Ereignis) | `serverEvents 'log'` → `recordLogLine` + `broadcast` | `BuildService.Event.log`, `Logs/LogBuffer.swift:56` `record` | `App/Shell/ServerLifecycle.swift:30` → `App/Shell/BuildMonitor.swift:42` | anders (AsyncStream) |
| `server:discover` | `serverDiscovery.ts:discoverServers` | `Build/ServerScan.swift:118` `ServerScan.discover` | `App/Pages/Server/DiscoveredServersSection.swift:160` | da |
| `server:kill` | `serverDiscovery.ts:killServer` | `Build/ServerScan.swift:170` `ServerScan.stop` | `App/Pages/Server/DiscoveredServersSection.swift:178` | da |
| `sitePreview:highlight` | `previewHighlight.ts:highlightInPreview` | `Plugins/PreviewScript.swift:129` `PreviewScript.call` | `App/Components/EditorPreview.swift:329` (`evaluateJavaScript` im eigenen WKWebView) | da |

## build / logs / projectPrefs

| Kanal | QC | QuartzHub Kern | App | Stand |
|---|---|---|---|---|
| `build:run` | handler: `joinRunningBuild`, `assertOutputFree`, `buildOutputGuard.assessOutputDir`, Rückfrage, `buildService.runBuild` | `Build/BuildService.swift:182` `build`, `:199` `joinRunningBuild`, `Build/BuildOutputGuard.swift:58` `assess` | `App/Components/BuildAction.swift:21-38` (aus `BuildServerModel.swift:111`, `PublishModel.swift:176`) | da |
| `build:log` (Ereignis) | `serverEvents 'buildLog'` → `broadcast` | `BuildService.Event.log` | `App/Shell/ServerLifecycle.swift:30` → `App/Shell/BuildMonitor.swift:42` | anders (AsyncStream) |
| `build:activity` | `buildService.ts:getBuildActivity` | `Build/BuildService.swift:173` `activity` | `App/Shell/BuildMonitor.swift:67` | da |
| `build:activityChanged` (Ereignis) | `serverEvents 'activity'` → `broadcast` | `BuildService.Event.activity` | `App/Shell/BuildMonitor.swift:39` | anders (AsyncStream) |
| `logs:history` | `logBuffer.ts:logHistory` | `Logs/LogBuffer.swift:66` `history` (ohne App-Aufruf) | `App/Shell/BuildMonitor.swift:49` `logs(_:)` hält die Zeilen selbst ab Start | anders (der Monitor abonniert ab Start, nichts nachzulesen) |
| `logs:clear` | `logBuffer.ts:clearLogHistory` | `Logs/LogBuffer.swift:70` `clear` | `App/Shell/BuildMonitor.swift:59` (aus `BuildServerPage.swift:101`, `:221`) | da |
| `build:lastOutput` | `buildService.ts:getBuildOutput` | `Build/BuildOutput.swift:42` `BuildOutput.info` | `App/Pages/Server/BuildServerModel.swift:82`, `App/Pages/Overview/OverviewModel.swift:105` | da |
| `projectPrefs:get` | `projectPrefsService.ts:getPrefs` | `Projects/ProjectPrefsStore.swift:12` `read` | `App/Pages/Server/BuildServerModel.swift:71`, `App/Pages/Publish/PublishModel.swift:83` | da |
| `projectPrefs:save` | `projectPrefsService.ts:savePrefs` | `Projects/ProjectPrefsStore.swift:24` `update` (`:17` `write`) | `App/Pages/Server/BuildServerModel.swift:143`, `App/Pages/Publish/PublishModel.swift:138` | da |

## sync

| Kanal | QC | QuartzHub Kern | App | Stand |
|---|---|---|---|---|
| `sync:run` | `syncService.ts:runSync` | `Git/Sync.swift:43` `Sync.run` | `App/Pages/GitSync/GitSyncModel.swift:112` | da |
| `sync:status` | `gitStatusService.ts:getGitStatus` | `Git/GitStatus.swift:58` `GitStatus.read` | `App/Pages/GitSync/GitSyncModel.swift:91`, `App/Pages/Overview/OverviewModel.swift:60` | da |

## backup

| Kanal | QC | QuartzHub Kern | App | Stand |
|---|---|---|---|---|
| `backup:listContentFolders` | `backupService.ts:listContentBackups` | `Projects/ContentBackups.swift:86` `list` | `App/Pages/Snapshots/SnapshotsModel.swift:82` | da |
| `backup:restoreContentFolder` | `backupService.ts:restoreContentBackup` | `Projects/ContentBackups.swift:112` `restore` | `App/Pages/Snapshots/SnapshotsModel.swift:225` | da |
| `backup:deleteContentFolder` | `backupService.ts:deleteContentBackup` | `Projects/ContentBackups.swift:104` `delete` | `App/Pages/Snapshots/SnapshotsModel.swift:234` | da |

## content

| Kanal | QC | QuartzHub Kern | App | Stand |
|---|---|---|---|---|
| `content:status` | `contentService.ts:getContentStatus` | `Projects/ContentFolder.swift:28` `ContentFolder.status` | `App/Pages/Config/ContentFolderSection.swift:83`, `App/Pages/Overview/OverviewModel.swift:56` | da |
| `content:change` | `contentService.ts:changeContentSource` | `Projects/ContentFolder+Source.swift:17` `changeSource` | `App/Pages/Config/ContentFolderSection.swift:155` | da |
| `content:progress` (Ereignis) | Callback von `changeContentSource` → `broadcast` | `progress`-Closure von `changeSource` | `App/Pages/Config/ContentFolderSection.swift:150`, `:158` | anders (Closure statt Ereigniskanal) |
| `content:createIndex` | `contentService.ts:createIndexPage` | `Projects/ContentIndexPage.swift:47` `ContentIndexPage.create` | `App/Pages/Config/ContentFolderSection.swift:235` | da |
| `content:formUsages` | `contentService.ts:formUsages` | `Projects/FormUsages.swift:198` `FormUsages.scan` | `App/Pages/Plugins/FormsTab.swift:488` | da |

## settings

| Kanal | QC | QuartzHub Kern | App | Stand |
|---|---|---|---|---|
| `settings:get` | `settingsService.ts:getSettings` | `Formats/SettingsStore.swift:10` `SettingsStore.read` | `App/Settings/SettingsWindow.swift:52`, `App/Shell/ServerLifecycle.swift:35` | da |
| `settings:save` | `settingsService.ts:saveSettings` + `applyTheme`/`applyAppMenu`/`applyRuntimeMode` | `Formats/SettingsStore.swift:15` `SettingsStore.update` | `App/Settings/SettingsWindow.swift:57`, `App/Shell/ServerLifecycle.swift:153` | da |
| `settings:appInfo` | `settingsService.ts:getAppInfo` (Version, Profilpfad, Cache-Größe, unlesbare Dateien) | Einzelteile: `Storage/JSONStore.swift` `quarantinedFiles`, `Themes/StyleSettingsSchema.swift:202` `cacheStats` | `App/Settings/SettingsWindow.swift:246`, `:270`, `:278`, `:285` (Bundle-Version direkt) | anders (die App liest die Teile einzeln, kein Sammelaufruf) |
| `settings:environment` | `environmentService.ts:getEnvironmentInfo` | `Environment/EnvironmentReport.swift:37` `EnvironmentReport.probe` | `App/Settings/SettingsWindow.swift:221`, `App/Projects/ProjectsModel.swift:38` | da |
| `settings:clearThemeDocsCache` | `styleSettingsSchemaService.ts:clearThemeDocsCache` | `Themes/StyleSettingsSchema.swift:214` `clearCache()` | `App/Settings/SettingsWindow.swift:269` | da |

## dialog

| Kanal | QC | QuartzHub Kern | App | Stand |
|---|---|---|---|---|
| `dialog:pickFolder` | `showOpenDialog({openDirectory})` | — (App-Sache) | `App/Projects/ProjectsModel.swift:82` `pickFolder` (aus `SettingsWindow.swift:106`, `ContentFolderSection.swift:112`, …) | anders (NSOpenPanel in der App) |
| `dialog:revealUserData` | `shell.showItemInFolder(userData/settings.json)` | — | `App/Settings/SettingsWindow.swift:282` | anders (NSWorkspace.activateFileViewerSelecting) |
| `dialog:openHandbook` | `menu.ts:openHandbook` | `Handbook.url` | `HelpCommands`, `HandbookLink` | gemessen (2026-11-13) |
| `dialog:openExternal` | `shell.openExternal` (nur https) | — | `App/Projects/ProjectInspector.swift:109`, `App/Pages/Plugins/PluginInspector.swift:40`, `App/Pages/GitSync/GitSyncPage.swift:175` | anders (SwiftUI `Link`/`openURL`) |
| `dialog:confirm` | `dialog.showMessageBox` | — | `App/Components/Confirm.swift:10` `Confirm.ask` (z. B. `ConnectionsSettings.swift:261`), `confirmationDialog` (z. B. `ProjectsWindow.swift:87`) | anders (native Dialoge in der App) |

## app (main → renderer)

| Kanal | QC | QuartzHub Kern | App | Stand |
|---|---|---|---|---|
| `app:navigate` (Ereignis) | `menu.ts:navigateRenderer('/settings')` | — | `App/QuartzHubApp.swift:62` (`Settings`-Szene), `App/QuartzHubApp.swift:76` (`ProjectCommands`, `openWindow`) | anders (SwiftUI-Szenen und `openWindow`/`openSettings`) |
| `app:command` (Ereignis) | `menu.ts:commandRenderer('save')` | — | `App/Shell/UnsavedGuard.swift:161` `SaveCommand` (`FocusedValue` `pageSave`), eingebunden `App/QuartzHubApp.swift:52` | anders (SwiftUI-Commands mit FocusedValue) |
