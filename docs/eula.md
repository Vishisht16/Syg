# Syg EULA

The Syg end-user licence agreement, version 1. It comes with each release of
Syg as `EULA.md`, and applies to the release it comes with.

This agreement is between you and Vishisht Mishra, who makes Syg ("we"). It
covers the `syg` program in every form we publish it: the release archives,
the Linux packages, the container image, the Homebrew formula and the Scoop
manifest, together with the documentation (together, "Syg"). By installing,
copying or using Syg, you accept this agreement. If you do not accept it, do
not use Syg. If you accept it for an organization, you confirm that you may
bind the organization to it, and "you" then means the organization.

## 1. What you may do

We grant you a free, worldwide, non-exclusive licence to install and use Syg,
for any purpose, commercial use included, on any number of machines, by
anyone who works for you or with you.

You may make the copies of Syg that using it needs:

- in your build and CI pipelines, and in the container and machine images you
  build for them;
- in mirrors, package repositories and artifact caches inside your
  organization;
- as backups.

Each copy keeps this agreement and the notices that come with Syg.

## 2. What you may not do

Unless we give you permission in writing, you may not:

- modify, adapt or translate Syg, or make works based on it;
- reverse engineer, decompile or disassemble Syg, except where the law allows
  it despite this restriction, and then only as far as it does;
- give, sell, rent, lend or sublicense Syg to anyone outside your
  organization, or publish copies of it, other than by pointing them to where
  we publish it: <https://github.com/vishisht16/syg>, the installers at
  <https://syg.vishisht.tech>, and the image and package channels named
  there;
- remove or change the notices that come with Syg;
- use the name Syg to suggest that we endorse something we do not.

To ask for a permission, write to <syg@vishisht.tech>.

## 3. What is yours

Syg claims no rights over what you write or what it makes from it. Your
modules, your configuration, and the manifests, findings and reports Syg
produces from them are yours.

## 4. Usage statistics

Syg sends anonymous usage statistics, as [the privacy page](privacy.md)
describes: what is sent, what never is, and where it goes. They are off when
you set `SYG_TELEMETRY=off` or `DO_NOT_TRACK=1`, or run `syg telemetry off`,
and accepting this agreement does not require you to leave them on.

## 5. Other components

Syg includes open-source components, each under its own licence. Those
licences, not this agreement, govern those components, and nothing here
limits what they allow. Their notices are in `THIRD_PARTY_NOTICES.txt`, which
comes with every release, and the software bill of materials of each release
lists them.

## 6. Updates

Syg checks for a newer release at most once a day, as the privacy page
describes, and only says so; it never updates itself. A later release may come
with a later version of this agreement, which then applies to that release.

## 7. No warranty

Syg is provided "as is", without warranty of any kind, express or implied,
including the warranties of merchantability, fitness for a particular purpose,
and non-infringement. Syg's checks find many mistakes, but not every mistake:
a clean result is not a guarantee that a deployment is correct, secure or
available. What you deploy, and how, remains your decision and your
responsibility.

## 8. Limitation of liability

To the extent the law allows, we are not liable for any indirect, incidental,
special, consequential or exemplary damages, or for lost profits, revenue,
data or use, arising from Syg or from this agreement, even if we were told
they were possible. To the extent the law allows, our total liability for
anything arising from Syg or this agreement is limited to the amount you paid
us for Syg. Where the law does not allow a limitation, the limitation applies
as far as the law does allow.

## 9. End of the licence

This licence ends at once if you break this agreement. You must then stop
using Syg and delete your copies of it. Sections 3, 7, 8 and 9 continue to
apply after it ends.

## 10. The whole agreement

This is the whole agreement between you and us about Syg. If a court finds a
part of it unenforceable, the rest still applies. Not enforcing a part of it
is not giving it up. You are responsible for following the laws that apply to
your use of Syg, including export laws.
