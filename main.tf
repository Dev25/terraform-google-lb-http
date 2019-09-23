/*
 * Copyright 2017 Google Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

resource "google_compute_global_forwarding_rule" "http" {
  project    = var.project
  count      = var.http_forward ? 1 : 0
  name       = var.name
  target     = google_compute_target_http_proxy.default[0].self_link
  ip_address = google_compute_global_address.default[0].address
  port_range = "80"
}

resource "google_compute_global_forwarding_rule" "https" {
  project    = var.project
  count      = var.ssl ? 1 : 0
  name       = "${var.name}-https"
  target     = google_compute_target_https_proxy.default[0].self_link
  ip_address = google_compute_global_address.default[0].address
  port_range = "443"
}

resource "google_compute_global_address" "default" {
  count      = var.create_address ? 1 : 0
  project    = var.project
  name       = "${var.name}-address"
  ip_version = var.ip_version
}

# HTTP proxy when ssl is false
resource "google_compute_target_http_proxy" "default" {
  project = var.project
  count   = var.http_forward ? 1 : 0
  name    = "${var.name}-http-proxy"
  url_map = compact(concat([var.url_map], google_compute_url_map.default.*.self_link), )[0]
}

# HTTPS proxy  when ssl is true
resource "google_compute_target_https_proxy" "default" {
  project          = var.project
  count            = var.ssl ? 1 : 0
  name             = "${var.name}-https-proxy"
  url_map          = compact(concat([var.url_map], google_compute_url_map.default.*.self_link), )[0]
  ssl_certificates = compact(concat(var.ssl_certificates, google_compute_ssl_certificate.default.*.self_link, ), )
  ssl_policy       = var.ssl_policy
  # quic_override
}

resource "google_compute_ssl_certificate" "default" {
  project     = var.project
  count       = var.ssl && ! var.use_ssl_certificates ? 1 : 0
  name_prefix = "${var.name}-certificate-"
  private_key = var.private_key
  certificate = var.certificate

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_url_map" "default" {
  project         = var.project
  count           = var.create_url_map ? 1 : 0
  name            = "${var.name}-url-map"
  default_service = google_compute_backend_service.default[keys(var.backends)[0]].self_link

}

resource "google_compute_backend_service" "default" {
  for_each = var.backends

  project = var.project
  name    = "${var.name}-backend-${each.key}"

  port_name   = lookup(each.value, "port_name", null)
  protocol    = lookup(each.value, "protocol", null)
  timeout_sec = lookup(each.value, "timeout_sec", null)

  health_checks   = [google_compute_health_check.default[each.key].self_link]
  enable_cdn      = lookup(each.value, "enable_cdn", false)
  security_policy = var.security_policy

  dynamic "backend" {
    for_each = each.value["groups"]
    content {
      balancing_mode               = lookup(backend.value, "balancing_mode", null)
      capacity_scaler              = lookup(backend.value, "capacity_scaler", null)
      description                  = lookup(backend.value, "description", null)
      group                        = lookup(backend.value, "group", null)
      max_connections              = lookup(backend.value, "max_connections", null)
      max_connections_per_instance = lookup(backend.value, "max_connections_per_instance", null)
      max_connections_per_endpoint = lookup(backend.value, "max_connections_per_endpoint", null)
      max_rate                     = lookup(backend.value, "max_rate", null)
      max_rate_per_instance        = lookup(backend.value, "max_rate_per_instance", null)
      max_rate_per_endpoint        = lookup(backend.value, "max_rate_per_endpoint", null)
      max_utilization              = lookup(backend.value, "max_utilization", null)
    }
  }

  #  dynamic "cdn_policy" {
  #   for_each = [lookup(each.value, "cdn_policy", {})]

  #   content {
  #     signed_url_cache_max_age_sec = null

  #     dynamic "cache_key_policy" {
  #       for_each =  [lookup(cdn_policy.value, "cache_key_policy", {})]
  #       content {
  #         include_host = true
  #       }
  #     }
  #   }
  # }


}

resource "google_compute_health_check" "default" {
  for_each = var.backends
  project  = var.project
  name     = "${var.name}-backend-${each.key}"

  check_interval_sec  = lookup(each.value["health_check"], "check_interval_sec", 5)
  timeout_sec         = lookup(each.value["health_check"], "timeout_sec", 5)
  healthy_threshold   = lookup(each.value["health_check"], "healthy_threshold", 2)
  unhealthy_threshold = lookup(each.value["health_check"], "unhealthy_threshold", 2)

  dynamic "http_health_check" {
    for_each = lookup(each.value["health_check"], "http_health_check", {}) == {} ? [] : [each.value["health_check"]["http_health_check"]]
    content {
      host         = lookup(http_health_check.value, "host", null)
      request_path = lookup(http_health_check.value, "request_path", null)
      response     = lookup(http_health_check.value, "response", null)

      port               = lookup(http_health_check.value, "port", null)
      port_name          = lookup(http_health_check.value, "port_name", null)
      port_specification = lookup(http_health_check.value, "port_specification", null)
    }
  }

  dynamic "https_health_check" {
    for_each = lookup(each.value["health_check"], "https_health_check", {}) == {} ? [] : [each.value["health_check"]["https_health_check"]]

    content {
      host         = lookup(https_health_check.value, "host", null)
      request_path = lookup(https_health_check.value, "request_path", null)
      response     = lookup(https_health_check.value, "response", null)

      port               = lookup(https_health_check.value, "port", null)
      port_name          = lookup(https_health_check.value, "port_name", null)
      port_specification = lookup(https_health_check.value, "port_specification", null)
    }
  }

  dynamic "http2_health_check" {
    for_each = lookup(each.value["health_check"], "http2_health_check", {}) == {} ? [] : [each.value["health_check"]["http2_health_check"]]

    content {
      host         = lookup(http2_health_check.value, "host", null)
      request_path = lookup(http2_health_check.value, "request_path", null)
      response     = lookup(http2_health_check.value, "response", null)

      port               = lookup(http2_health_check.value, "port", null)
      port_name          = lookup(http2_health_check.value, "port_name", null)
      port_specification = lookup(http2_health_check.value, "port_specification", null)
    }
  }

}

# resource "google_compute_firewall" "default-hc" {
#   count         = length(var.firewall_networks)
#   project       = length(var.firewall_networks) == 1 && var.firewall_projects[0] == "default" ? var.project : var.firewall_projects[count.index]
#   name          = "${var.name}-hc-${count.index}"
#   network       = length(var.firewall_networks) == 1 ? var.firewall_networks[0] : var.firewall_networks[count.index]
#   source_ranges = [
#     "130.211.0.0/22",
#     "35.191.0.0/16",
#     "209.85.152.0/22",
#     "209.85.204.0/22"]
#   target_tags   = var.target_tags

#   dynamic "allow" {
#     for_each = distinct(var.backend_params)
#     content {
#       protocol = "tcp"
#       ports    = [
#         split(",", allow.value)[2]]
#     }
#   }
# }
