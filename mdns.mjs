// Announces this install on the local network as productowner.local (multicast DNS, like a network printer), so
// people open https://productowner.local instead of a number. Runs only on "this network" installs on Linux
// (install.sh turns it on); Docker Desktop on Windows/macOS keeps it from reaching the network.
//   MDNS_NAME=productowner.local  MDNS_IP=192.168.1.20  node mdns.mjs
import dgram from "node:dgram";

const NAME = (process.env.MDNS_NAME || "productowner.local").toLowerCase().replace(/\.$/, "");
const IP = process.env.MDNS_IP || "";
const GROUP = "224.0.0.251";
const PORT = 5353;

/** The name in a DNS message at `at`: labels, possibly compressed. */
export function readName(buf, at) {
  const labels = [];
  let jumped = false;
  let end = at;
  for (let guard = 0; guard < 64; guard++) {
    const len = buf[at];
    if (len === undefined) return null;
    if (len === 0) {
      if (!jumped) end = at + 1;
      return { name: labels.join(".").toLowerCase(), end };
    }
    if ((len & 0xc0) === 0xc0) {
      if (!jumped) end = at + 2;
      at = ((len & 0x3f) << 8) | buf[at + 1];
      jumped = true;
      continue;
    }
    labels.push(buf.toString("utf8", at + 1, at + 1 + len));
    at += 1 + len;
  }
  return null;
}

/** Does this query ask for our name (A or ANY)? */
export function asksFor(buf, name = NAME) {
  if (buf.length < 12 || buf[2] & 0x80) return false; // too short, or an answer
  const qd = buf.readUInt16BE(4);
  let at = 12;
  for (let i = 0; i < qd; i++) {
    const q = readName(buf, at);
    if (!q || q.end + 4 > buf.length) return false;
    const type = buf.readUInt16BE(q.end);
    if (q.name === name && (type === 1 || type === 255)) return true;
    at = q.end + 4;
  }
  return false;
}

/** The answer: name → IPv4, cache-flush class, 2 minutes. */
export function answer(name, ip) {
  const labels = Buffer.concat([...name.split(".").map((l) => Buffer.concat([Buffer.from([Buffer.byteLength(l)]), Buffer.from(l)])), Buffer.from([0])]);
  const head = Buffer.from([0, 0, 0x84, 0, 0, 0, 0, 1, 0, 0, 0, 0]);
  const rr = Buffer.alloc(10);
  rr.writeUInt16BE(1, 0); // A
  rr.writeUInt16BE(0x8001, 2); // IN, cache flush
  rr.writeUInt32BE(120, 4);
  rr.writeUInt16BE(4, 8);
  return Buffer.concat([head, labels, rr, Buffer.from(ip.split(".").map(Number))]);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  if (!/^(\d{1,3}\.){3}\d{1,3}$/.test(IP)) {
    console.error("MDNS_IP isn't set; nothing to announce.");
    process.exit(0);
  }
  const reply = answer(NAME, IP);
  const sock = dgram.createSocket({ type: "udp4", reuseAddr: true });
  const send = () => sock.send(reply, PORT, GROUP);
  sock.on("message", (msg) => asksFor(msg) && send());
  sock.on("error", (e) => console.error(`mDNS: ${e.message}`));
  sock.bind(PORT, () => {
    try {
      sock.addMembership(GROUP, IP);
    } catch {
      sock.addMembership(GROUP);
    }
    sock.setMulticastTTL(255);
    console.log(`Announcing ${NAME} → ${IP} on the local network.`);
    send();
    setTimeout(send, 1000); // announce twice, as the standard asks
  });
}
