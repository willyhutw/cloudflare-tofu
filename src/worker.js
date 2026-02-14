const CF_API = "https://api.cloudflare.com/client/v4";

async function checkHealth(env) {
  try {
    const response = await fetch(`http://${env.HOMELAB_IPV4}/health`, {
      headers: { Host: env.DOMAIN },
      signal: AbortSignal.timeout(5000),
    });
    return response.ok;
  } catch {
    return false;
  }
}

async function getDnsRecords(env, type) {
  const response = await fetch(
    `${CF_API}/zones/${env.CLOUDFLARE_ZONE_ID}/dns_records?name=${env.DOMAIN}&type=${type}`,
    { headers: { Authorization: `Bearer ${env.CLOUDFLARE_API_TOKEN}` } }
  );
  const data = await response.json();
  return data.result || [];
}

async function updateDnsRecord(env, recordId, type, content, comment) {
  await fetch(`${CF_API}/zones/${env.CLOUDFLARE_ZONE_ID}/dns_records/${recordId}`, {
    method: "PATCH",
    headers: {
      Authorization: `Bearer ${env.CLOUDFLARE_API_TOKEN}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ content, comment, proxied: false }),
  });
}

async function switchDns(env, target) {
  const ipv4 = target === "homelab" ? env.HOMELAB_IPV4 : env.GITHUB_IPV4;
  const ipv6 = target === "homelab" ? env.HOMELAB_IPV6 : env.GITHUB_IPV6;
  const comment = `Switched to ${target} by dns-failover worker at ${new Date().toISOString()}`;

  const aRecords = await getDnsRecords(env, "A");
  const aaaaRecords = await getDnsRecords(env, "AAAA");

  for (const record of aRecords) {
    await updateDnsRecord(env, record.id, "A", ipv4, comment);
  }
  for (const record of aaaaRecords) {
    await updateDnsRecord(env, record.id, "AAAA", ipv6, comment);
  }

  console.log(`DNS switched to ${target} (A: ${ipv4}, AAAA: ${ipv6})`);
}

export default {
  async scheduled(event, env, ctx) {
    const healthy = await checkHealth(env);
    const aRecords = await getDnsRecords(env, "A");

    if (aRecords.length === 0) {
      console.log("No A records found");
      return;
    }

    const currentIp = aRecords[0].content;
    const pointingToHomelab = currentIp === env.HOMELAB_IPV4;

    if (healthy && !pointingToHomelab) {
      console.log("Homelab is UP, switching DNS to homelab...");
      await switchDns(env, "homelab");
    } else if (!healthy && pointingToHomelab) {
      console.log("Homelab is DOWN, switching DNS to GitHub Pages...");
      await switchDns(env, "github");
    } else {
      console.log(`No change needed (healthy: ${healthy}, target: ${pointingToHomelab ? "homelab" : "github"})`);
    }
  },
};
