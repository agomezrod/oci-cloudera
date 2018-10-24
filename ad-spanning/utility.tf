resource "oci_core_instance" "UtilityNode" {
  count               = "${var.UtilityNodeCount}"
  availability_domain = "${lookup(data.oci_identity_availability_domains.ADs.availability_domains[count.index%3],"name")}"
  compartment_id      = "${var.compartment_ocid}"
  display_name        = "CDH Utility ${count.index+1}"
  hostname_label      = "CDH-Utility-${count.index+1}"
  shape               = "${var.MasterInstanceShape}"
  subnet_id           = "${oci_core_subnet.public.*.id[count.index%3]}"

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

data "oci_core_vnic_attachments" "utility_node_vnics" {
  compartment_id      = "${var.compartment_ocid}"
  availability_domain = "${lookup(data.oci_identity_availability_domains.ADs.availability_domains[0],"name")}"
  instance_id         = "${oci_core_instance.UtilityNode.*.id[0]}"
}

data "oci_core_vnic" "utility_node_vnic" {
  vnic_id = "${lookup(data.oci_core_vnic_attachments.utility_node_vnics.vnic_attachments[0],"vnic_id")}"
}