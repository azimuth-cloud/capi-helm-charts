#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.14"
# dependencies = [
#     "openstacksdk>=4.20.0",
# ]
# ///
import argparse
import pathlib
import json
import openstack
import logging
import sys
import time

parser = argparse.ArgumentParser()
parser.add_argument("flatcar_sysext_manifest", type=pathlib.Path)
parser.add_argument("--arches", default=["x86_64"], nargs="+")
parser.add_argument("--debug", action="store_true")
parser.add_argument(
    "--output",
    default="outputs.txt",
    help="File to append the matrices to, in GitHub Actions output format. Pass $GITHUB_OUTPUT in a workflow.",
)
args = parser.parse_args()

openstack.enable_logging(debug=args.debug)
conn = openstack.connect()
logger = logging.getLogger()
logging.basicConfig(stream=sys.stdout, level=logging.INFO)

with open(args.flatcar_sysext_manifest, "r") as f:
    manifest = json.load(f)

# Loop through the manifest, finding the image id of already existing images or queueing the image upload where required.
uploaded = {}
for version_name, version_data in manifest.items():
    for arch in args.arches:
        data = version_data[arch]
        # Only upload each image once. Images may be shared between multiple versions in the manifest.
        if data["name"] not in uploaded.keys():
            # If the image with the same name already exists, just find it's ID and store it.
            try:
                existing_image = conn.image.find_image(data["name"], ignore_missing=False)
                if existing_image.status == "active":
                    uploaded[data["name"]] = {"id": existing_image.id, "active": True}
                    logger.info("Found existing image for %s: %s", data["name"], existing_image.id)
                else:
                    sys.exit(
                        f"Found existing image for {data['name']}: {existing_image.id}, but the image status was {existing_image.status}."
                        " Investigate the problem then run the script again."
                    )
            # If the image doesn't exist, queue an upload.
            except openstack.exceptions.NotFoundException:
                # Image properties are provided in the manifest as a list of "key=value" strings.
                properties = dict(p.split("=", 1) for p in data.get("properties", []))
                image_queued = conn.image.create_image(
                    name=data["name"],
                    disk_format="qcow2",
                    container_format="bare",
                    visibility="private",
                    properties=properties
                    | {
                        "hw_scsi_model": "virtio-scsi",
                        "hw_disk_bus": "scsi",
                    },
                )
                conn.image.import_image(image_queued, method="web-download", uri=data["url"])
                uploaded[data["name"]] = {
                    "id": image_queued.id,
                    "active": False,
                }
                logger.info("Queued upload of image %s: %s", data["name"], image_queued.id)

# Wait for images whose uploads we queued to complete.
for name, data in uploaded.items():
    counter = 0
    while data["active"] is False:
        uploaded_image = conn.image.get_image(data["id"])
        if uploaded_image.status == "active":
            data["active"] = True
            logger.info("Confirmed %s: %s was uploaded successfully.", name, data["id"])
        else:
            logger.info("%s: %s not yet in active state. Waiting (attempt %s)", name, data["id"], counter)
            time.sleep(30)
            counter += 1
            if counter >= 10:  # Try for 5 minutes
                sys.exit(
                    f"Uploaded image {name} ({data['id']}) failed to reach active status."
                    " Investigate the problem then run the script again."
                )


# Transform the manifest into lists to be consumed directly by github actions matrices:
#   latest:  one item per arch, to test a clean deployment of the newest version.
#   upgrade: one item per arch and pair of consecutive versions, to test each upgrade step.
def version_key(version_data):
    """Get the numberical k8s version for sorting."""
    return tuple(int(part) for part in version_data["kubernetes_version"].lstrip("v").split("."))


def dns_label(*parts):
    """Join parts into a DNS-safe label, for use in k8s names."""
    return "-".join(parts).lower().replace("_", "-").replace(".", "-")


def minor_version(item):
    """Get the major.minor k8s version of a matrix item, e.g. v1.36.4 -> 1.36"""
    return ".".join(item["kubernetes_version"].lstrip("v").split(".")[:2])


def version_item(version_data, arch):
    """Generate a matrix item for a version."""
    data = version_data[arch]
    sysexts = data["sysexts"]
    return {
        "kubernetes_version": version_data["kubernetes_version"],
        "image_id": uploaded[data["name"]]["id"],
        "values": {
            "osDistro": "flatcar-sysext",
            "flatcar": {
                "sysexts": {
                    sysext: {
                        "url": sysexts[sysext]["url"],
                        "checksum": sysexts[sysext]["checksum_sha512"],
                    }
                    for sysext in ["kubernetes", "containerd"]
                }
            },
        },
    }


versions = sorted(manifest.values(), key=version_key)
latest = []
upgrade = []
for arch in args.arches:
    items = [version_item(version_data, arch) for version_data in versions]
    latest.append({"arch": arch, "label": dns_label(arch, minor_version(items[-1]), "latest")} | items[-1])
    upgrade.extend(
        {
            "arch": arch,
            "label": dns_label(arch, minor_version(from_item), "to", minor_version(to_item)),
            "from": from_item,
            "to": to_item,
        }
        for from_item, to_item in zip(items, items[1:])
    )

logger.info("Writing the matrices to %s", args.output)
with open(args.output, "a") as f:
    f.write(f"latest={json.dumps(latest)}\n")
    f.write(f"upgrade={json.dumps(upgrade)}\n")
