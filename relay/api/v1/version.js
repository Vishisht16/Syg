import { waitUntil } from "@vercel/functions";
import { version } from "../../lib/relay.js";

export function GET(request) {
  return version(request, { waitUntil });
}
