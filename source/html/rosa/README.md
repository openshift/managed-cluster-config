Source for these templates is here:
* https://openshift.github.io/oauth-templates/rosa/errors.html
* https://openshift.github.io/oauth-templates/rosa/login.html
* https://openshift.github.io/oauth-templates/rosa/providers.html

### PS
Note that providers.html is a bit different than upstream because the upstream is missing

```html
{{ if ne $provider.Name "kube:admin" }}
{{ end }}
```

same for osd, too...

To stuff them in the correct place in this repo run `make generate-oauth-templates`.