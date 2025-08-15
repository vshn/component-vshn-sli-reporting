// main template for vshn-sli-reporting
local common = import 'common.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.vshn_sli_reporting;

local netPol = function(targetNS)
  kube.NetworkPolicy('allow-from-%s' % params.namespace) {
    metadata+: {
      labels+: common.Labels,
      namespace: targetNS,
    },
    spec+: {
      ingress_: {
        allowFromReportNs: {
          from: [
            {
              namespaceSelector: {
                matchLabels: {
                  name: params.namespace,
                },
              },
            },
          ],
        },
      },
    },
  };

{
  Policies: std.filterMap(
    function(name) params.network_policies.target_namespaces[name] == true,
    function(name) netPol(name),
    std.objectFields(params.network_policies.target_namespaces),
  ),
}
