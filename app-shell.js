(function(){
  const cfg=window.GUIDRENT_CONFIG||{};
  window.GuidrentUI={
    toast(message){const el=document.getElementById('toast');if(!el)return;el.textContent=message;el.classList.add('show');clearTimeout(window.__guidrentToast);window.__guidrentToast=setTimeout(()=>el.classList.remove('show'),2600)},
    money(value,currency='GHS'){return new Intl.NumberFormat('en-GH',{style:'currency',currency,maximumFractionDigits:0}).format(Number(value||0))},
    date(value){return value?new Date(value).toLocaleString('en-GH',{dateStyle:'medium',timeStyle:'short'}):'—'},
    status(value){const safe=String(value||'unknown').replace(/_/g,' ');return `<span class="status ${String(value||'')}">${safe}</span>`},
    configured(){return Boolean(window.GuidrentBackend?.configured)},
    contactEmail(){return cfg.SUPPORT_EMAIL||'support@example.com'}
  };
})();
