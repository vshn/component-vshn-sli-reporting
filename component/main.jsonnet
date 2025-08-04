// main template for vshn-sli-reporting
local common = import 'common.libsonnet';
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local netPol = import 'networkpolicies.libsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.vshn_sli_reporting;


local formatImage = function(ref) '%(registry)s/%(repository)s:%(tag)s' % ref;

local lieutenantSecret = kube.Secret('lieutenant-credentials') {
  metadata+: {
    namespace: params.namespace,
    labels+: common.Labels,
  },
  stringData: {
    [name]: params.lieutenant[name]
    for name in std.objectFields(params.lieutenant)
  },
};

local authSecret = kube.Secret('vshn-sli-reporting-auth') {
  metadata+: {
    namespace: params.namespace,
    labels+: common.Labels,
  },
  stringData: {
    [name]: params.auth[name]
    for name in std.objectFields(params.auth)
  },
};

local env = [
  {
    name: 'VSR_AUTH_USER',
    value: params.auth.user,
  },
  {
    name: 'VSR_AUTH_PASS',
    valueFrom: {
      secretKeyRef: {
        name: authSecret.metadata.name,
        key: 'password',
      },
    },
  },
  {
    name: 'VSR_LIEUTENANT_NAMESPACE',
    value: params.lieutenant.namespace,
  },
  {
    name: 'VSR_LIEUTENANT_SA_TOKEN',
    valueFrom: {
      secretKeyRef: {
        name: lieutenantSecret.metadata.name,
        key: 'sa_token',
      },
    },
  },
  {
    name: 'VSR_LIEUTENANT_K8S_URL',
    valueFrom: {
      secretKeyRef: {
        name: lieutenantSecret.metadata.name,
        key: 'k8s_url',
      },
    },
  },
];

local pvcs = [
  kube.PersistentVolumeClaim(name) {
    metadata+: {
      labels+: common.Labels,
    },
    spec+: com.makeMergeable(params.pvcs[name]),
  }
  for name in std.objectFields(params.pvcs)
];

local container = {
  image: formatImage(params.images.sli_reporting),
  command: [ 'sh', '-c' ],
  args: [ 'vshn-sli-reporting', 'serve' ],
  ports: [
    {
      containerPort: params.server.port,
    },
  ],
  [if std.length(params.volumes) > 0 then 'volumeMounts']: [
    { name: name } + params.volumes[name].mount_spec
    for name in std.objectFields(params.volumes)
  ],
  env: env,
};

local sts = kube.StatefulSet('vshn-sli-reporting') {
  metadata+: {
    namespace: params.namespace,
    labels+: common.Labels,
  },
  spec+: {
    template+: {
      metadata+: {
        labels+: common.Labels,
      },
      spec+: {
        initContainers: [
          container {
            name: 'db-init',
            args: [
              'vshn-sli-reporting db init --db-file ' + params.db_file,
            ],
          },
        ],
        containers: [
          container {
            name: 'vshn-sli-reporting',
            args: [
              'vshn-sli-reporting serve --auth-user ${VSR_AUTH_USER} --auth-pass ${VSR_AUTH_PASS} --lieutenant-namespace ${VSR_LIEUTENANT_NAMESPACE} --lieutenant-k8s-url ${VSR_LIEUTENANT_K8S_URL} --lieutenant-sa-token ${VSR_LIEUTENANT_SA_TOKEN} --db-file ' + params.db_file + ' --port ' + std.toString(params.server.port) + ' --host ' + params.server.host,
            ],
          },
        ],
        [if std.length(params.volumes) > 0 then 'volumes']: [
          { name: name } + params.volumes[name].volume_spec
          for name in std.objectFields(params.volumes)
        ],
      },
    },
  },
};

{
  '00_namespace': kube.Namespace(params.namespace) {
    metadata+: {
      labels+: common.Labels,
    } + com.makeMergeable(params.namespaceMetadata),
  },
  '01_netpols': netPol.Policies,
  '10_auth_secret': authSecret,
  '10_lieutenant_secret': lieutenantSecret,
  '20_pvc': pvcs,
  '30_sts': sts,
}
