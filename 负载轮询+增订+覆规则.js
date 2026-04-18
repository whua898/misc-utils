/**
 * Mihomo Party「高级配置重建脚本」
 * 版本：V16.0 (终极纪委·非破坏性重建版)
 * 更新内容：
 * 1. 【架构升级】采用“新对象重建”代替“就地清创”。脚本不再修改原始配置，而是返回一个全新的配置对象，更加安全、专业。
 * 2. 【保留扩展】通过 `keepKeys` 数组，用户可以轻松指定需要从原始配置中保留的顶级键。
 * 3. 继承 V15.2 的所有优点：模块化、数字命名、URL标准化等。
 */

function main(config) {

  // ==================================================================
  // ==================== 1. 定义区 (Definitions) ====================
  // ==================================================================

  // (1) 用户自定义订阅链接
  const subscriptionLinks = [
    'http://35.212.131.96:28038/56ff8aef-19a9-4043-8d4c-d38361c8f651/proxies',
    'http://35.212.145.196:28038/56ff8aef-19a9-4043-8d4c-d38361c8f651/proxies',
    'http://35.212.201.53:28038/56ff8aef-19a9-4043-8d4c-d38361c8f651/proxies',
    'http://35.212.203.48:28038/56ff8aef-19a9-4043-8d4c-d38361c8f651/proxies',
    'http://35.212.149.232:28038/56ff8aef-19a9-4043-8d4c-d38361c8f651/proxies',
  ];

  // (2) 需要从原始配置中保留的顶级键列表 (可按需添加)
  const keepKeys = [
    'proxies',           // 静态节点
    'proxy-providers',   // 代理提供者
    'secret',            // API 访问密码
    'sniffer',           // 嗅探器配置
    'geodata-mode',      // GeoIP/GeoSite 数据模式
  ];

  // (3) 内部常量与函数 (已按要求调整顺序)
  const normalizeUrl = (u) => String(u || '').trim().replace(/\/+$/, '');
  const mrs_defaults = { type: 'http', format: 'mrs', behavior: 'domain', interval: 86400 };
  const provider_defaults = { interval: 86400, 'health-check': { enable: true, interval: 600, url: 'http://www.gstatic.com/generate_204' } };
  const health_check_defaults = { url: 'http://www.gstatic.com/generate_204', interval: 300, timeout: 3000, 'max-failed-times': 3 };

  // (4) 圣衣模板
  const templateConfig = {
    'mixed-port': 7890,
    'allow-lan': false,
    'mode': 'rule',
    'ipv6': false,
    'log-level': 'info',
    'external-controller': '127.0.0.1:9090',

    'dns': {
      enable: true, listen: '0.0.0.0:53', ipv6: false,
      'default-nameserver': ['223.5.5.5', '114.114.114.114'],
      nameserver: ['223.5.5.5', '114.114.114.114', '119.29.29.29', '180.76.76.76'],
      'enhanced-mode': 'fake-ip',
      'fake-ip-range': '198.18.0.1/16',
      'fake-ip-filter': ["*.lan", "*.localdomain", "*.example", "*.invalid", "*.localhost", "*.test", "*.local", "*.home.arpa", "router.asus.com", "localhost.sec.qq.com", "localhost.ptlogin2.qq.com", "+.msftconnecttest.com"]
    },

    'tun': {
      enable: true, stack: 'system', 'auto-route': true, 'auto-detect-interface': true,
      'dns-hijack': ['any:53', 'tcp://any:53']
    },

    'proxy-groups': [
        { name: "🔝 节点选择", type: "select", proxies: ["🔄 轮询均衡", "⛓️ 保持均衡", "⚡ 自动选择", "🎯 全球直连"], "include-all": true },
        { name: "🔄 轮询均衡", type: "load-balance", strategy: "round-robin", ...health_check_defaults, "include-all": true },
        { name: "⛓️ 保持均衡", type: "load-balance", strategy: "consistent-hashing", ...health_check_defaults, "include-all": true },
        { name: "⚡ 自动选择", type: "url-test", tolerance: 50, ...health_check_defaults, "include-all": true },
        { name: "▶️ YouTube", type: "select", proxies: ["🔝 节点选择", "⚡ 自动选择"] },
        { name: "🔎 Google", type: "select", proxies: ["🔝 节点选择", "⚡ 自动选择"] },
        { name: "🐙 GitHub", type: "select", proxies: ["🔝 节点选择", "🎯 全球直连"] },
        { name: "✈️ 电报信息", type: "select", proxies: ["🔝 节点选择", "🎯 全球直连"] },
        { name: "Ⓜ️ 微软服务", type: "select", proxies: ["🎯 全球直连", "🔝 节点选择"] },
        { name: "🍏 苹果服务", type: "select", proxies: ["🎯 全球直连", "🔝 节点选择"] },
        { name: "🐟 漏网之鱼", type: "select", proxies: ["🔝 节点选择", "🔄 轮询均衡", "⛓️ 保持均衡", "🎯 全球直连", "⚡ 自动选择"] },
        { name: "🎯 全球直连", type: "select", proxies: ["DIRECT"] },
        { name: "🚫 全球拦截", type: "select", proxies: ["REJECT"] },
        // AI服务专用组 - 直连避免代理冲突
        { name: "🤖 AI服务直连", type: "select", proxies: ["DIRECT"] }
    ],

    'rules': [
      // Microsoft Store 和 UWP 应用网络直连规则 - 必须放在最前面（基于微软官方文档）
      // Microsoft 核心域名
      'DOMAIN-SUFFIX,microsoft.com,DIRECT,no-resolve',
      'DOMAIN-SUFFIX,storeedge.microsoft.com,DIRECT,no-resolve',
      'DOMAIN-SUFFIX,*.microsoft.com,DIRECT,no-resolve',
      // Windows 更新和系统服务
      'DOMAIN-SUFFIX,windows.net,DIRECT,no-resolve',
      'DOMAIN-SUFFIX,windows.com,DIRECT,no-resolve',
      'DOMAIN-SUFFIX,windowsupdate.com,DIRECT,no-resolve',
      'DOMAIN-SUFFIX,*.windowsupdate.com,DIRECT,no-resolve',
      'DOMAIN-SUFFIX,*.wns.windows.com,DIRECT,no-resolve',
      'DOMAIN-SUFFIX,wustat.windows.com,DIRECT,no-resolve',
      // 网络连接检测
      'DOMAIN-SUFFIX,msftncsi.com,DIRECT,no-resolve',
      'DOMAIN-SUFFIX,*.msftncsi.com,DIRECT,no-resolve',
      'DOMAIN-SUFFIX,msftconnecttest.com,DIRECT,no-resolve',
      // 微软账户和认证
      'DOMAIN-SUFFIX,live.com,DIRECT,no-resolve',
      'DOMAIN-SUFFIX,*.live.com,DIRECT,no-resolve',
      'DOMAIN-SUFFIX,login.live.com,DIRECT,no-resolve',
      'DOMAIN-SUFFIX,account.live.com,DIRECT,no-resolve',
      'DOMAIN-SUFFIX,hotmail.com,DIRECT,no-resolve',
      'DOMAIN-SUFFIX,*.hotmail.com,DIRECT,no-resolve',
      'DOMAIN-SUFFIX,outlook.com,DIRECT,no-resolve',
      'DOMAIN-SUFFIX,*.outlook.com,DIRECT,no-resolve',
      'DOMAIN-SUFFIX,clientconfig.passport.net,DIRECT,no-resolve',
      // Office 和生产力
      'DOMAIN-SUFFIX,office.com,DIRECT,no-resolve',
      'DOMAIN-SUFFIX,*.office.com,DIRECT,no-resolve',
      'DOMAIN-SUFFIX,office365.com,DIRECT,no-resolve',
      'DOMAIN-SUFFIX,*.office365.com,DIRECT,no-resolve',
      // 其他微软服务
      'DOMAIN-SUFFIX,xboxlive.com,DIRECT,no-resolve',
      'DOMAIN-SUFFIX,*.xboxlive.com,DIRECT,no-resolve',
      'DOMAIN-SUFFIX,aka.ms,DIRECT,no-resolve',
      'DOMAIN-SUFFIX,mp.microsoft.com,DIRECT,no-resolve',
      'DOMAIN-SUFFIX,*.mp.microsoft.com,DIRECT,no-resolve',
      // AI服务路由规则 - 根据国内访问情况分类
      'DOMAIN-SUFFIX,lingma.aliyun.com,🎯 全球直连,no-resolve',  // 通义灵码 - 国内直连
      'DOMAIN-SUFFIX,jetbrains.com,🔝 节点选择,no-resolve',      // JetBrains AI - 可能需要代理
      'DOMAIN-SUFFIX,ai.jetbrains.com,🔝 节点选择,no-resolve',   // JetBrains AI 服务
      'DOMAIN-SUFFIX,openai.com,🔝 节点选择,no-resolve',         // OpenAI - 必须代理
      'DOMAIN-SUFFIX,anthropic.com,🔝 节点选择,no-resolve',      // Claude - 必须代理
      // 原有规则
      'RULE-SET,Reject,🚫 全球拦截,no-resolve', 'RULE-SET,OpenAI,🔝 节点选择,no-resolve',
      'RULE-SET,GitHub,🐙 GitHub,no-resolve', 'RULE-SET,YouTube,▶️ YouTube,no-resolve',
      'RULE-SET,Google,🔎 Google,no-resolve', 'RULE-SET,Bilibili,🔝 节点选择,no-resolve',
      'RULE-SET,Telegram,✈️ 电报信息,no-resolve', 'RULE-SET,Microsoft,Ⓜ️ 微软服务,no-resolve',
      'RULE-SET,Apple,🍏 苹果服务,no-resolve', 'RULE-SET,Proxy,🔝 节点选择,no-resolve',
      'RULE-SET,Direct,🎯 全球直连,no-resolve', 'GEOIP,CN,🎯 全球直连', 'MATCH,🐟 漏网之鱼'
    ],

    'rule-providers': {
      'YouTube':   { ...mrs_defaults, url: normalizeUrl("https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/youtube.mrs"), path: "./ruleset/YouTube.mrs" },
      'Google':    { ...mrs_defaults, url: normalizeUrl("https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/google.mrs"), path: "./ruleset/Google.mrs" },
      'GitHub':    { ...mrs_defaults, url: normalizeUrl("https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/github.mrs"), path: "./ruleset/GitHub.mrs" },
      'OpenAI':    { ...mrs_defaults, url: "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/openai.mrs", path: "./ruleset/OpenAI.mrs" },
      'Bilibili':  { ...mrs_defaults, url: "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/bilibili.mrs", path: "./ruleset/Bilibili.mrs" },
      'Reject':    { ...mrs_defaults, url: "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/category-ads-all.mrs", path: "./ruleset/Reject.mrs" },
      'Telegram':  { ...mrs_defaults, url: "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/telegram.mrs", path: "./ruleset/Telegram.mrs" },
      'Microsoft': { ...mrs_defaults, url: "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/microsoft.mrs", path: "./ruleset/Microsoft.mrs" },
      'Apple':     { ...mrs_defaults, url: "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/apple.mrs", path: "./ruleset/Apple.mrs" },
      'Proxy':     { ...mrs_defaults, url: "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/gfw.mrs", path: "./ruleset/Proxy.mrs" },
      'Direct':    { ...mrs_defaults, url: "https://raw.githubusercontent.com/MetaCubeX/meta-rules-dat/meta/geo/geosite/cn.mrs", path: "./ruleset/Direct.mrs" }
    }
  };


  // ==================================================================
  // ==================== 2. 核心逻辑 (Core Logic) ====================
  // ==================================================================

  // ✅ 非破坏性重建：从原始 config 中筛选出需要保留的键，创建一个全新的配置对象。
  const preserved = Object.fromEntries(Object.entries(config).filter(([k]) => keepKeys.includes(k)));
  const newConfig = { ...preserved };

  // 从新配置对象中获取原始 providers
  const originalProxyProviders = newConfig['proxy-providers'] || {};

  // ✅ 纪委去重
  const finalProxyProviders = {};
  const seenUrls = new Set();

  const allProvidersToProcess = [
    ...Object.entries(originalProxyProviders),
    ...subscriptionLinks.map((link, index) => [
      `Subscription-${index + 1}`,
      { url: link, type: 'http', path: `./providers/Subscription-${index + 1}.yaml`, ...provider_defaults }
    ])
  ];

  for (const [name, provider] of allProvidersToProcess) {
    if (provider && provider.url && provider.url.startsWith('http')) {
      const nu = normalizeUrl(provider.url);
      if (seenUrls.has(nu)) continue;
      seenUrls.add(nu);
      finalProxyProviders[name] = { ...provider, url: nu };
    } else if (provider) {
      finalProxyProviders[name] = provider;
    }
  }
  
  // 将处理好的 providers 更新到新配置对象上
  newConfig['proxy-providers'] = finalProxyProviders;

  // ✅ 圣衣移植：将模板配置应用到新配置对象上 (会覆盖同名键)
  Object.assign(newConfig, templateConfig);

  // 返回全新的配置对象
  return newConfig;
}