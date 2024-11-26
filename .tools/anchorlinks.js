/* anchorlinks.js: add anchor links before headers h2, h3
*/
document.addEventListener("DOMContentLoaded", function () {
    const headers = document.querySelectorAll("h2, h3" );
    var css_needed = false;

    headers.forEach(header => {
        if (header.id) {
            css_needed = true
            // create anchor
            const anchor = document.createElement("a");
            anchor.href = `#${header.id}`;
            anchor.textContent = "#";
            anchor.className = "header-anchor";
            // insert after header
            header.appendChild(anchor);
        }
    });

    if (css_needed) {
        const style = document.createElement("style");
        style.appendChild(document.createTextNode(`
            .header-anchor {
                display: inline-block;
                text-decoration: none;
                margin-left: 8px;
                font-size: 0.8em;
                opacity: 0.5;
            }
            
            .header-anchor:hover {
                opacity: 1;
                text-decoration: underline;
            }
        `));
        document.head.appendChild(style);        
    }
});