import { connect } from "cloudflare:sockets";

const CF_API = "https://api.cloudflare.com/client/v4";

async function checkHealth(env) {
  try {
    const socket = connect({ hostname: env.HOMELAB_IPV4, port: 80 });
    const writer = socket.writable.getWriter();
    await writer.write(new TextEncoder().encode(
      `GET /health/ HTTP/1.1\r\nHost: ${env.DOMAIN}\r\nConnection: close\r\n\r\n`
    ));
    writer.releaseLock();

    const reader = socket.readable.getReader();
    const { value } = await reader.read();
    await socket.close();

    const text = new TextDecoder().decode(value);
    const statusCode = parseInt(text.split(" ")[1]);
    return statusCode >= 200 && statusCode < 300;
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
