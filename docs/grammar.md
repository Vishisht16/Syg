# Grammar

The complete grammar of the language, in EBNF. Names are linked by reference to a declaration, never by a string that must match: no production lets a program write a selector, a target reference or a backend name.

```ebnf
file          := module_decl , { top_decl } ;
module_decl   := "module" , module_name ;
module_name   := IDENT , { "." , IDENT } ;      (* "platform.paved" *)
ref           := IDENT | IDENT , "." , IDENT ;  (* a name, or alias.name into an import *)

top_decl      := import_decl | extern_decl | service_decl | job_decl
               | stateful_decl | config_decl | secret_decl | identity_decl
               | policy_decl | environment_decl | profile_decl
               | relate_decl | raw_decl ;

import_decl   := "import" , STRING , [ "as" , IDENT ] ;

profile_decl  := [ "internal" ] , "profile" , IDENT , "(" , [ IDENT , { "," , IDENT } ] , ")" ,
                 "{" , { profile_item } , "}" ;
profile_item  := [ "locked" | "default" ] , ( service_item | security_field )
               | "required" , IDENT ;   (* an item kind, or "digest": every image pinned *)
use_item      := "use" , ref , "(" , [ IDENT , ":" , ( STRING | INT ) , { "," , IDENT , ":" , ( STRING | INT ) } ] , ")" ;
               (* inside a profile, any STRING or INT may be a parameter reference, PARAM := "$" IDENT *)

environment_decl := "environment" , IDENT , "{" , { "namespace" , STRING
                    | IDENT , "{" , { override_item } , "}"       (* a workload *)
                    | config_decl } , "}" ;
override_item := "replicas" , INT | "image" , ( "tag" | "digest" ) , STRING | resources_blk
               | "scale" , [ "at" , ( PERCENT | QUANTITY ) ] , [ "between" , INT , "and" , INT ]
               | disruption_blk | rollout_blk | expose_item | env_item
               | labels_blk | annotations_blk | qos_item ;     (* per key *)

raw_decl      := "raw" , STRING , ref , "{" , [ "yaml" , STRING ] , "}" ;
                 (* header "GROUP/VERSION/Kind"; the body is usually a block string *)
block_string  := '"""' , { any character } , '"""' ;   (* raw, dedented; a STRING *)

service_decl  := "service" , IDENT , "{" , { service_item } , "}" ;
service_item  := "image" , STRING
               | "replicas" , INT
               | "port" , IDENT , INT , [ IDENT ]
               | "use" , IDENT , [ "(" , arg_list , ")" ]
               | "identity" , IDENT
               | "policy" , IDENT                      (* links a policy_decl *)
               | resources_blk | health_blk | needs_item | env_item
               | scale_item | disruption_blk | rollout_blk | security_blk
               | expose_item | internal_item | spread_blk | avoid_blk
               | tolerate_item | storage_blk | sidecar_blk
               | labels_blk | annotations_blk | qos_item ;

labels_blk    := "labels" , "{" , { meta_entry , [ "," ] } , "}" ;
annotations_blk := "annotations" , "{" , { meta_entry , [ "," ] } , "}" ;
meta_entry    := ( IDENT | QUALIDENT | STRING ) , "=" , STRING ;
                 (* keys are validated as the API server does; app.kubernetes.io/
                    name|instance|managed-by|part-of and syg.vishisht.tech/* are reserved *)
qos_item      := "qos" , ( "guaranteed" | "burstable" | "besteffort" ) ;

resources_blk := "resources" , "{" , { "cpu" , QUANTITY
                                    | "memory" , QUANTITY
                                    | "limits" , "{" , { QUANTITY_FIELD } , "}" } , "}" ;

health_blk    := "health" , "{" , { probe_kind , probe_spec } , "}" ;
probe_kind    := "live" | "ready" | "startup" ;
probe_spec    := ( "GET" , PORTREF , PATH | "TCP" , PORTREF | "EXEC" , STRING , { STRING } )
               (* EXEC: one string runs under /bin/sh -c; two or more are argv,
                  run with no shell *)
               , { probe_opt } ;
probe_opt     := "every" , DURATION | "timeout" , DURATION
               | "after" , DURATION | "failures" , INT ;

needs_item    := "needs" , ( "config" | "secret" ) , IDENT ,
                 [ ( "as" , IDENT ) | ( "at" , PATH ) ]
               | "needs" , "service" , IDENT , [ PORTREF ] ;
                 (* a dependency on a workload of the module or an extern service,
                    the depends-on edge CHK-NP-002 keeps open *)

scale_item    := "scale" , "on" , IDENT , "at" , ( PERCENT | QUANTITY ) ,
                 "between" , INT , "and" , INT ;

disruption_blk:= "disruption" , "{" , ( "minAvailable" , ( INT | PERCENT )
                                      | "maxUnavailable" , ( INT | PERCENT ) )
                                    , [ [ "," ] , "evictUnhealthy" , BOOL ] , "}" ;
                 (* commas between items are accepted *)

rollout_blk   := "rollout" , "{" , { "strategy" , ( "rolling" | "recreate" )
                                   | "maxUnavailable" , ( INT | PERCENT )
                                   | "maxSurge" , ( INT | PERCENT ) } , "}" ;

security_blk  := "security" , "{" , { ( "runAsNonRoot" | "readOnlyRootFilesystem"
                                      | "allowPrivilegeEscalation" ) , BOOL
                                    | ( "runAsUser" | "runAsGroup" | "fsGroup" ) , INT
                                    | ( "drop" | "add" ) , CAP , { "," , CAP }
                                    | "seccomp" , ( "RuntimeDefault" | "Unconfined" ) } , "}" ;
                 (* CAP is an upper-case capability name; fsGroup is workload-only *)

expose_item   := "expose" , PORTREF , "at" , STRING ,
                 [ "path" , STRING ] , [ "via" , ref ] , [ "tls" , IDENT ] ;
internal_item := "internal" , PORTREF ;

stateful_decl := "stateful" , IDENT , "{" , { workload_item } , "}" ;
job_decl      := "job"      , IDENT , "{" , { workload_item } , "}" ;

storage_blk   := "storage" , IDENT , "at" , STRING ,
                 [ "{" , { "size"   , QUANTITY
                         | "class"  , IDENT
                         | "access" , ACCESSMODE , { "," , ACCESSMODE } } , "}" ] ;
job_item      := "schedule"    , STRING     (* present => CronJob *)
               | "parallelism" , INT
               | "completions" , INT
               | "retries"     , INT
               | "deadline"    , DURATION ;
ACCESSMODE    := "ReadWriteOnce" | "ReadOnlyMany" | "ReadWriteMany"
               | "ReadWriteOncePod" ;

identity_decl := "identity" , IDENT , "{" , { grant } , "}" ;
policy_decl   := "policy" , IDENT , "{" , [ "ingress" , peers ] , [ "egress" , peers ] , "}" ;
peers         := "{" , [ peer , { [ "," ] , peer } ] , "}" ;
peer          := IDENT , [ PORTREF ] ;
                 (* A peer is a workload of the module, an extern service,
                    or "apiserver" (egress only, no port). An ingress port is the
                    linked workload's, an egress port the peer's. A block present
                    isolates that direction; either may come first, and the
                    formatter writes ingress first *)
grant         := "may" , verb , { "," , verb } ,
                 "on" , resource , { "," , resource } ,
                 [ "across" , "cluster" ] ;
verb          := IDENT | "*" ;
resource      := IDENT | "*" ;

extern_decl   := "extern" , KIND , IDENT , "{" , { extern_field } , "}"
               | "extern" , "topology" , ( IDENT | QUALIDENT ) , "{" , [ "domains" , INT ] , "}" ;
               | "extern" , "resource" , STRING , IDENT , "{" , "}"   (* "GROUP/VERSION/Kind" *)
               (* KIND: secret | config | service | identity | storageclass | gateway | host;
                  a host's fields: "address" STRING | port_item;
                  a gateway's fields: "namespace" STRING | "listener" IDENT;
                  a service's: port_item | "namespace" STRING.
                  topology: a node label key, and how many domains it has *)

spread_blk    := "spread" , "{" , "across" , topo_keys , [ "skew" , INT ] , [ "strict" | "soft" ] , "}" ;
avoid_blk     := "avoid" , "{" , "across" , topo_keys , [ "with" , ref , { "," , ref } ]
                                , [ "strict" | "soft" ] , "}" ;
topo_keys     := ( IDENT | QUALIDENT ) , { "," , ( IDENT | QUALIDENT ) } ;
tolerate_item := "tolerate" , ( IDENT | QUALIDENT ) , [ "=" , ( IDENT | QUALIDENT | STRING ) ]
                , [ ":" , EFFECT ] , [ "for" , DURATION ] ;
               (* EFFECT: NoSchedule | PreferNoSchedule | NoExecute (unsaid: every
                  effect); no value means Exists; `for` is tolerationSeconds, NoExecute only.
                  strict/soft unsaid means soft. An avoid without `with` keeps the workload's
                  own pods apart; `with` names workloads of the module, never selectors *)
relate_decl   := "relate" , APIVERSION , KIND , "{" , { relate_field } , "}" ;
relate_field  := "field" , FIELDPATH , relate_verb ;
relate_verb   := "references" , ( "service" | "config" | "secret" | "identity" )
               | "references" , "port" , "of" , "service"
               | "references" , GVK
               | "selects" , ( "service" | "workload" )
               | "produces" , ( "secret" | "config" )
               | "provides" , "host" | "requires" , "storageclass" ;
               (* APIVERSION: group/version written bare, cert-manager.io/v1, or v1;
                  FIELDPATH: dotted names, "[]" after a name traverses a list,
                  spec.http[].route[].destination.host;
                  GVK: group/version/Kind written bare, cert-manager.io/v1/ClusterIssuer,
                  naming a kind the module declares raw or extern *)

PORTREF       := ":" , IDENT ;
QUANTITY      := NUMBER , [ UNIT ] ;
PERCENT       := NUMBER , "%" ;
DURATION      := NUMBER , ( "s" | "m" | "h" ) ;
```
