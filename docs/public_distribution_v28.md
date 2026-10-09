# v28 public distribution and entry Save protection

The GitHub public distribution retains two longstanding privacy-related source
changes from the original public base. Natural-coast v28 hashes those inputs as
part of its gameplay authority. Consequently its authority identity differs from
the separately adopted editable/native distribution, even though the inspected
physical source, geometry and navigation producers are unchanged.

Keep natural-coast saves with the distribution that created them. Exact
same-distribution re-admission is supported; cross-distribution migration is not.
Loading an incompatible identity is refused. Do not rewrite save hashes or move
the original adopted smoke fixture into a new claim of public acceptance.

## This narrowly scoped UI update

Only the natural-coast entry view changes. Its ordinary Save button now checks
the complete identity of an existing destination before invoking the unchanged
adapter. Foreign, missing or malformed identities and unreadable/oversized files
are refused without replacing the existing file. Legitimate same-identity and
pending-action saves retain the original behavior. All 168 gameplay authority
input files, legacy modes and the adopted v28 production tree remain unchanged.

This protects the normal entry UI Save route. Direct adapter API callers and the
standalone basic view retain their original save boundary; this update does not
claim an all-API fix or protection against concurrent external file replacement.

## Verification boundary

The actual public-code QA project passed 63 unique checks for coastal_range:
the inherited Save-button signal, real adapter, pending-file roundtrip, exact
existing-file refusal and preserved temporary files/state. The real CJK FontFile
and font bytes were loaded and checked. The UI was built off-tree; no complete
game scene, OS mouse flow, clean import or export was tested by this gate.

The new versioned restore helper also journals each layer's own replacements.
An ordinary write failure restores those known preimages; a detected concurrent
edit is preserved and reported instead of being overwritten. This is not a
power-loss durability or concurrent-writer transaction guarantee.

The two-recipe public identity capture was resource-refused before engine launch
and is not claimed complete. The original native adopted-16 result and its
fixture remain preserved as native-only evidence. No independent public fixture
is supplied by this update. README stays blank and v25 remains withdrawn.
