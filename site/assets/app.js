const menu = document.querySelector('.nav-button');
if (menu) menu.addEventListener('click', () => {
  const nav = document.querySelector('nav');
  const open = nav.classList.toggle('open');
  menu.setAttribute('aria-expanded', String(open));
});
const search = document.querySelector('#api-search');
if (search) search.addEventListener('input', () => {
  const term = search.value.toLowerCase().trim();
  let count = 0;
  document.querySelectorAll('.api-item').forEach(item => {
    item.hidden = !item.textContent.toLowerCase().includes(term);
    if (!item.hidden) count++;
  });
  document.querySelector('#api-count').textContent = `${count} topics`;
});
