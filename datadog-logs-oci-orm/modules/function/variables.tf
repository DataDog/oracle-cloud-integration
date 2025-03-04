variable "freeform_tags" {
  type        = map(string)
  description = "A map of freeform tags to apply to the resources"
  default     = {}
}

variable "function_image_path" {
  type        = string
  description = "The full path of the function image. The image should be present in the container registry for the region"
}

variable "function_app_name" {
  type        = string
  description = "The name of the function application"
}

variable "function_app_ocid" {
  type        = string
  description = "The OCID of the function application"
}
