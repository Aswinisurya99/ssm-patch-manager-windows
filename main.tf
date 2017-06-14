resource "aws_ssm_patch_baseline" "baseline" {
  name             = "${var.envtype}-patch-baseline"
  description      = "${var.envtype} patch baseline"
  approved_patches = ["${var.approved_patches}"]
  rejected_patches = ["${var.rejected_patches}"]

  approval_rule {
    approve_after_days = 7

    patch_filter {
      key    = "PRODUCT"
      values = ["${var.product_versions}"]
    }

    patch_filter {
      key    = "CLASSIFICATION"
      values = ["${var.patch_classification}"]
    }

    patch_filter {
      key    = "MSRC_SEVERITY"
      values = ["${var.patch_severity}"]
    }
  }
}

resource "aws_ssm_patch_group" "patchgroup" {
  count       = "${length(var.patch_groups)}"
  baseline_id = "${aws_ssm_patch_baseline.baseline.id}"
  patch_group = "${element(var.patch_groups, count.index)}"
}

resource "aws_ssm_maintenance_window" "window" {
  name     = "${var.envtype}-patch-maintenance-window"
  schedule = "${var.maintenance_window_schedule}"
  duration = "${var.maintenance_window_duration}"
  cutoff   = "${var.maintenance_window_cutoff}"
}

resource "aws_ssm_maintenance_window_target" "target_scan" {
  count         = "${length(var.patch_groups)}"
  window_id     = "${aws_ssm_maintenance_window.window.id}"
  resource_type = "INSTANCE"

  targets {
    key    = "tag: Patch Group"
    values = ["${element(var.patch_groups, count.index)}"]
  }
}

resource "aws_ssm_maintenance_window_target" "target_install" {
  window_id     = "${aws_ssm_maintenance_window.window.id}"
  resource_type = "INSTANCE"

  targets {
    key    = "tag: Patch Group"
    values = ["${element(var.patch_groups, 1)}"]
  }
}

resource "aws_ssm_maintenance_window_task" "task_scan_patches" {
  window_id        = "${aws_ssm_maintenance_window.window.id}"
  task_type        = "RUN_COMMAND"
  task_arn         = "AWS-ApplyPatchBaseline"
  priority         = 1
  service_role_arn = "${aws_iam_role.ssm_maintenance_window.arn}"
  max_concurrency  = "10"
  max_errors       = "2"

  targets {
    key    = "WindowTargetIds"
    values = ["${aws_ssm_maintenance_window_target.target_scan.*.id}"]
  }

  task_parameters {
    name   = "Operation"
    values = ["Scan"]
  }
}

resource "aws_ssm_maintenance_window_task" "task_install_patches" {
  window_id        = "${aws_ssm_maintenance_window.window.id}"
  task_type        = "RUN_COMMAND"
  task_arn         = "AWS-ApplyPatchBaseline"
  priority         = 2
  service_role_arn = "${aws_iam_role.ssm_maintenance_window.arn}"
  max_concurrency  = "10"
  max_errors       = "2"

  targets {
    key    = "WindowTargetIds"
    values = ["${aws_ssm_maintenance_window_target.target_install.*.id}"]
  }

  task_parameters {
    name   = "Operation"
    values = ["Install"]
  }
}

data "aws_iam_policy_document" "ssm_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com", "ssm.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ssm_maintenance_window" {
  name               = "ssm-maintenance-window-role"
  path               = "/system/"
  assume_role_policy = "${data.aws_iam_policy_document.ssm_assume_role_policy.json}"
}

resource "aws_iam_role_policy_attachment" "role_attach" {
  role       = "${aws_iam_role.ssm_maintenance_window.name}"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonSSMMaintenanceWindowRole"
}