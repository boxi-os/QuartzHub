// page-scripts: the code that runs inside the export window, on a page of the user's built site
// (QuartzControl's export/pageScripts.ts and the three functions of shared/exportModel.ts it is
// handed as source there). Bundled for the browser, not for Node, and loaded into the export
// window's own content world (ExportWindow), so the site's scripts neither see nor change it.
//
// src/export/ holds both files as QuartzControl 1.3.0 has them, unchanged: the same code runs in
// WebKit that ran in Chromium, and what differs is the engine. PageScriptsTests checks the copies
// against the sha256 recorded by scripts/page-scripts-golden.mjs.
import { epubChapters, extractArticle, fillPageNumbers, findDocumentProblems, imagesSettled, readNavigation, settlePage } from './export/pageScripts'
import { anchorFor, outsideUrl, slugFromPathname } from './export/exportModel'

;(globalThis as Record<string, unknown>).__quartzHubExport = {
  settlePage, readNavigation, extractArticle, findDocumentProblems, imagesSettled, fillPageNumbers, epubChapters,
  slugFromPathname, anchorFor, outsideUrl
}
