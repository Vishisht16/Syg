# Syg EULA

The Syg end-user licence agreement, version 1. It comes with each release of
Syg as `EULA.md`, and applies to the release it comes with.

This agreement is between you and Vishisht Mishra, who makes Syg ("we"). It
covers the `syg` program in every form we publish it (the release archives,
the Linux packages and the container image), together with its documentation
(together, "Syg"). By installing, copying or using Syg, you accept this
agreement. If you do not accept it, do not use Syg. If you accept it for an
organization, you confirm that you may bind the organization to it, and "you"
then means the organization.

The tools that install Syg (the install scripts, the GitHub Action, the
Homebrew formula and the Scoop manifest) are published under the MIT licence,
in their own repositories. What they install is Syg, under this agreement.

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

Syg sends anonymous usage statistics, as the privacy page,
<https://syg.vishisht.tech/privacy>, describes: what is sent, what never is,
and where it goes. They are off when you set `SYG_TELEMETRY=off` or
`DO_NOT_TRACK=1`, or run `syg telemetry off`, and accepting this agreement
does not require you to leave them on.

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

## 8. High-risk use

Syg is not designed, made or licensed for use where its failure, or a mistake
it does not catch, could lead to death, personal injury, or severe physical or
environmental damage: in operating nuclear facilities, aircraft navigation or
communication, air traffic control, life-support systems or weapons, for
example. Do not rely on Syg there. If you use it there anyway, you do so
entirely at your own risk.

## 9. Limitation of liability

To the extent the law allows, we are not liable for any indirect, incidental,
special, consequential or exemplary damages, or for lost profits, revenue,
data or use, arising from Syg or from this agreement, even if we were told
they were possible. To the extent the law allows, our total liability for
anything arising from Syg or this agreement is limited to the amount you paid
us for Syg. Where the law does not allow a limitation, the limitation applies
as far as the law does allow.

## 10. End of the licence

This licence ends at once if you break this agreement. You must then stop
using Syg and delete your copies of it. Sections 3 and 7 to 12 continue to
apply after it ends.

## 11. The law that governs it

This agreement is governed by the laws of India, without regard to their rules
on conflicts of laws. The courts at New Delhi, India, have exclusive
jurisdiction over any dispute arising out of or in connection with this
agreement or Syg. Nothing in it takes away a protection that the law of the
country you live in gives you and that no agreement can exclude.

## 12. The whole agreement

This is the whole agreement between you and us about Syg. If a court finds a
part of it unenforceable, the rest still applies. Not enforcing a part of it
is not giving it up. You are responsible for following the laws that apply to
your use of Syg, including export laws.
