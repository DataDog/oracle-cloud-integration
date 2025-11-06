data "external" "stack_info" {
  program = ["python", "${path.module}/stack_id_from_job.py"]
  query   = {}
}
