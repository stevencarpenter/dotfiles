# DOM checks

Use the rendered DOM to confirm suspected visual defects. For static sites, the built HTML can also reveal missing build transformations. Source inspection identifies the cause after the output demonstrates the problem.

## Links

Inspect the actual `href` and its resolved destination. Check whether an apparent Markdown or repository path is a broken navigation link or an intentional downloadable source file.

If a link transformation is missing, compare an affected rendered page with the source and the plugin's registered API. Do not change plugin registration based only on whether an export is named or default.

## Headings and landmarks

Inspect heading order in the page's reading context. Check that headings express the visible hierarchy and label their sections. A heading-count search is a diagnostic hint, not a complete accessibility test.

Verify a main-content landmark and any navigation labels needed to distinguish repeated regions. Not every page requires a header, navigation menu, and footer.

## Images and controls

Check that informative images have an appropriate accessible description and decorative images have empty alternative text. Inspect linked images and icon-only controls for an accessible name.

Confirm that visual badges and buttons link to or trigger the intended behavior. Do not add text arrows or labels solely because an element contains a link.

## Metadata and generated styles

Check canonical URLs, social images, or print styles when the task includes them. Resolve referenced assets against their actual host; an externally hosted social image need not exist in the local build directory.

For lower heading levels or transformed Markdown, compare computed styles with the intended hierarchy. Missing selectors are only a cause if those styles should apply to the affected element.

## Evidence

Report the observed page, viewport, element, and failing behavior. Confirm broken destinations or missing transformations directly. A text search match alone does not establish a visual or accessibility defect.
