# Vagrant Terraform dummy box

To turn this into a box:

```
$ tar cvzf dummy.box ./metadata.json ./Vagrantfile
```

Use it
```
vagrant --provider=terraform box add --name terraform dummy.box
```
