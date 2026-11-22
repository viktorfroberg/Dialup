// Screenshots open in a small "picture viewer" window over the page instead of leaving it.
// Without JavaScript the links still open the image itself.
(function () {
  var links = Array.prototype.slice.call(document.querySelectorAll('.shot a'));
  if (!links.length) return;
  var index = 0;
  var box = document.createElement('div');
  box.className = 'viewer';
  box.hidden = true;
  box.innerHTML =
    '<div class="viewer-window" role="dialog" aria-modal="true" aria-labelledby="viewer-title">' +
      '<div class="viewer-titlebar"><span id="viewer-title"></span><button class="viewer-close" aria-label="Close">&times;</button></div>' +
      '<div class="viewer-picture"><img alt=""></div>' +
      '<div class="viewer-toolbar">' +
        '<button class="viewer-prev">&#9664; Previous</button>' +
        '<span class="viewer-count"></span>' +
        '<button class="viewer-next">Next &#9654;</button>' +
        '<a class="viewer-full" target="_blank" rel="noopener">Full size</a>' +
      '</div>' +
    '</div>';
  document.body.appendChild(box);
  var img = box.querySelector('img');
  var title = box.querySelector('#viewer-title');
  var count = box.querySelector('.viewer-count');
  var full = box.querySelector('.viewer-full');

  function show(i) {
    index = (i + links.length) % links.length;
    var link = links[index];
    var name = link.parentNode.querySelector('b').textContent;
    img.src = link.href;
    img.alt = link.querySelector('img').alt;
    title.textContent = name + ' - Dialup Picture Viewer';
    count.textContent = (index + 1) + ' of ' + links.length;
    full.href = link.href;
    box.hidden = false;
    document.documentElement.classList.add('viewer-open');
    box.querySelector('.viewer-next').focus();
  }
  function close() {
    box.hidden = true;
    document.documentElement.classList.remove('viewer-open');
    links[index].focus();
  }
  links.forEach(function (link, i) {
    link.addEventListener('click', function (e) { e.preventDefault(); show(i); });
  });
  box.querySelector('.viewer-close').addEventListener('click', close);
  box.querySelector('.viewer-prev').addEventListener('click', function () { show(index - 1); });
  box.querySelector('.viewer-next').addEventListener('click', function () { show(index + 1); });
  box.addEventListener('click', function (e) { if (e.target === box) close(); });
  document.addEventListener('keydown', function (e) {
    if (box.hidden) return;
    if (e.key === 'Escape') close();
    else if (e.key === 'ArrowLeft') show(index - 1);
    else if (e.key === 'ArrowRight') show(index + 1);
  });
})();
