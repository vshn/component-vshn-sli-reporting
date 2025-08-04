local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.vshn_sli_reporting;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('vshn-sli-reporting', params.namespace);

local appPath =
  local project = std.get(std.get(app, 'spec', {}), 'project', 'syn');
  if project == 'syn' then 'apps' else 'apps-%s' % project;

{
  ['%s/vshn-sli-reporting' % appPath]: app,
}
