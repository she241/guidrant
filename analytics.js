(function(){
  const cfg=window.GUIDRENT_CONFIG||{};
  window.GuidrentAnalytics={track(name,properties={}){try{const choice=JSON.parse(localStorage.getItem('guidrentCookieChoiceV1')||'{}');if(!cfg.ENABLE_ANALYTICS||!choice.analytics)return;console.info('[Guidrent analytics]',name,properties)}catch{}}};
})();
