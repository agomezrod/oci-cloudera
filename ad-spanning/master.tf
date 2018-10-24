resource "oci_core_instance" "MasterNode" {
  count               = "${var.MasterNodeCount}"
  availability_domain = "${lookup(data.oci_identity_availability_domains.ADs.availability_domains[count.index%3],"name")}"
  compartment_id      = "${var.compartment_ocid}"
  display_name        = "CDH Master ${format("%01d", count.index+1)}"
  hostname_label      = "CDH-Master-${format("%01d", count.index+1)}"
  shape               = "${var.MasterInstanceShape}"
  subnet_id           = "${oci_core_subnet.private.*.id[count.index%3]}"

  source_details {
    source_type             = "image"
    source_id               = "${var.InstanceImageOCID[var.region]}"
    boot_volume_size_in_gbs = "${var.boot_volume_size}"
  }

  metadata {
    ssh_authorized_keys = "${var.ssh_public_key}"
    user_data           = "${base64encode(file("../scripts/boot.sh"))}"
  }

  timeouts {
    create = "30m"
  }
}
