resource "oci_core_instance" "sandbox" {
  availability_domain = "${lookup(data.oci_identity_availability_domains.availability_domains.availability_domains[0], "name")}"
  compartment_id      = "${var.compartment_ocid}"
  display_name        = "cdh-sandbox"
  hostname_label      = "cdh-sandbox"
  shape               = "${var.shape}"
  subnet_id           = "${oci_core_subnet.public.*.id[0]}"

  source_details {
    source_type = "image"
    source_id   = "${var.images[var.region]}"
  }

  metadata {
    ssh_authorized_keys = "${var.ssh_public_key}"
    user_data           = "${base64encode(file("sandbox.sh"))}"
  }
}

data "oci_core_vnic_attachments" "sandbox_vnics" {
  compartment_id      = "${var.compartment_ocid}"
  availability_domain = "${lookup(data.oci_identity_availability_domains.availability_domains.availability_domains[0], "name")}"
  instance_id         = "${oci_core_instance.sandbox.id}"
}

data "oci_core_vnic" "sandbox_vnic" {
  vnic_id = "${lookup(data.oci_core_vnic_attachments.sandbox_vnics.vnic_attachments[0], "vnic_id")}"
}

output "1 - Sandbox IP" { value = "${data.oci_core_vnic.sandbox_vnic.public_ip_address}" }
output "2 - Cloudera Guided Demo" { value = "http://${data.oci_core_vnic.sandbox_vnic.public_ip_address}" }
output "3 - HUE Login" { value = "http://${data.oci_core_vnic.sandbox_vnic.public_ip_address}:8888" }
output "4 - Cloudera Manager Login" { value = "http://${data.oci_core_vnic.sandbox_vnic.public_ip_address}:7180" }