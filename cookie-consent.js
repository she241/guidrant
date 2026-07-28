(function(){
  const key='guidrentCookieChoiceV1';
  if(localStorage.getItem(key))return;
  const bar=document.createElement('div');
  bar.setAttribute('role','dialog');bar.setAttribute('aria-label','Cookie choices');
  bar.style.cssText='position:fixed;left:16px;right:16px;bottom:16px;z-index:9999;max-width:760px;margin:auto;background:#061a37;color:white;padding:16px;border-radius:16px;box-shadow:0 18px 60px rgba(0,0,0,.3);font:14px system-ui';
  bar.innerHTML='<b>Privacy choices</b><p style="margin:7px 0 12px;color:#d7e2f1">Guidrent uses essential browser storage for sign-in, saved homes and security. Optional analytics remain off unless you accept them.</p><div style="display:flex;gap:8px;flex-wrap:wrap"><button id="essentialOnly" style="padding:9px 12px;border:0;border-radius:10px;font-weight:800">Essential only</button><button id="acceptAnalytics" style="padding:9px 12px;border:0;border-radius:10px;background:#08a44f;color:white;font-weight:800">Allow analytics</button><a href="cookies.html" style="padding:9px;color:white">Cookie details</a></div>';
  document.body.appendChild(bar);
  function save(analytics){localStorage.setItem(key,JSON.stringify({essential:true,analytics,at:new Date().toISOString()}));bar.remove();window.dispatchEvent(new CustomEvent('guidrent:consent',{detail:{analytics}}))}
  bar.querySelector('#essentialOnly').onclick=()=>save(false);bar.querySelector('#acceptAnalytics').onclick=()=>save(true);
})();
