// main template for vshn-sli-reporting
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.vshn_sli_reporting;

local labels = {
  'app.kubernetes.io/name': 'appuio-reporting',
  'app.kubernetes.io/managed-by': 'commodore',
  'app.kubernetes.io/part-of': 'syn',
};

{
  Labels: labels,
}
