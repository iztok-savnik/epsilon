# `epsilon` graph database system

`epsilon` is a storage manager, browser and querying facility for
knowledge graphs.

## Abstract data model

`epsilon` is based on the associative memory organization that
provides fast retrieval of facts and the associations among facts. It
is used for storing, querying and managing RDF knowledge graphs.

The associative memory organization uses symbols for the
representation of the facts. The symbols are linked by statements,
implemented as triples that bind two symbols together by the use of a
predicate. The associations among the statements are formed by means
of a ring (an equivalence class) that links triples having the same
property.

From the perspective of a graph data model, a symbol is represented by
a node and a triple is represented by a named edge of a graph. Each
edge (s,p,o) is connected into seven rings that correspond to all
possible subsets of {s,p,o}, i.e., to all possible keys of a triple
(s,p,o).

## Interactive environment

`epsilon` command line interface implements an interactive environment
for storing, browsing and querying knowledge graphs.

`epsilon` currently provides a simple means for querying triples. The
triple-patterns can be conveniently implemented by means of the
rings. User can explore rings by using keys as the entry points to the
rings. General SparQL queries can be currently implemented only as
Perl functions.

To be able to explore the conceptual levels of a knowledge graph we
developed a simple programming environment based on variables that
represent sets of nodes. The operations are provided for transforming
the sets to other sets. The transitive closure of a set of graph nodes
is based on the selected predicate. The levelwise computation of a
transitive closure can extract selected levels of the
closure. Further, the sets can be mapped by using a path of predicates
and regular path expressions.

`epsilon` includes a set of commands for the computation of the
statistics of knowledge graphs. The statistics is computed for the
schema triples that form a conceptual schema of a knowledge graph. The
schema triples of a knowledge graph are partially ordered. We can
choose to compute either coarse statistics or more fine grained
statistics by selecting the appropriate size of a schema graph.

The datasets used for the empirical study of the algorithm for the
computation of the statistics of knowledge graphs is presented here.

## Software

`epsilon` graph database system is implemented in Perl programming
language by using BerkeleyDB as a key-value store. The documentation
of modules is provided in POD format.

* `epsilon` - main interface
* `Mstore.pm` - epsilon triple-store
* `Kgraph.pm` - operations for managing knowledge graphs
* `Stat.pm` - statistics of knowledge graphs
* `KeyID.pm` - unique identifiers of RDF keys 

## Publications

* I.Savnik, K.Nitta, The design of `epsilon` store, FAMNIT,
  University of Primorska, in preparation, Jan 2020.

## Patents

* Generation apparatus, generation method and generation
  program. (Working title: Statistics of triple-store based on
  conceptual schemata) Kiyoshi Nitta, Iztok Savnik. Japan Patent
  Office: Patent Num. JP2018-84993A, 2020.

* Calculation device, calculation method, and calculation
  program. (Working title: Associative memory organization for fast
  retrieval of facts and the associations among facts) Kiyoshi Nitta,
  Iztok Savnik. Japan Patent Office: Patent Num. JP2018-85056A, 2020.

* Generation apparatus, generation method and generation
  program. (Working title: Statistics of triple-store based on
  conceptual schemata) Kiyoshi Nitta, Iztok Savnik. US Patent
  10,977,282, 2021.

* Calculation device, calculation method, and calculation
  program. (Working title: Associative memory organization for fast
  retrieval of facts and the associations among facts) Kiyoshi Nitta,
  Iztok Savnik. US Patent 10,885,453, 2021.

## Last update

Thu Feb 24 21:41:12 CET 2022