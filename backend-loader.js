document.addEventListener('DOMContentLoaded', async () => {
  if (!window.GuidrentBackend?.configured) return;
  try {
    const liveListings = await window.GuidrentBackend.listProperties({ limit: 100 });
    if (liveListings.length) {
      listings = liveListings;
      saved = JSON.parse(localStorage.getItem('guidrentSaved') || '[]');
      applyFilters();
      const liveTag = document.querySelector('.live-tag');
      if (liveTag) liveTag.textContent = 'Live database connected';
    }
  } catch (error) {
    console.warn('Guidrent backend connection failed; using bundled demo listings.', error);
  }
});
