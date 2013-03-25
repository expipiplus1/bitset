{-# LANGUAGE BangPatterns #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE GADTs #-}

-----------------------------------------------------------------------------
-- |
-- Module      :  Data.BitSet
-- Copyright   :  (c) Sergei Lebedev, Aleksey Kladov 2013
--                Based on Data.BitSet (c) Denis Bueno 2008-2009
-- License     :  MIT
-- Maintainer  :  superbobry@gmail.com
-- Stability   :  experimental
-- Portability :  GHC
--
-- A space-efficient implementation of set data structure for enumerated
-- data types.
--
-- /Note/: Read below the synopsis for important notes on the use of
-- this module.
--
-- This module is intended to be imported @qualified@, to avoid name
-- clashes with "Prelude" functions, e.g.
--
-- > import Data.BitSet (BitSet)
-- > import qualified Data.BitSet as BS
--
-- The implementation is abstract with respect to conatiner type, so any
-- numeric type with 'Bits' instance can be used as a container. However,
-- independent of container choice, the maximum number of elements in a
-- bit set is bounded by @maxBound :: Int@.
--
-- See "Data.BitSet.Dynamic" for a dynamic bit set implementation.

module Data.BitSet
    (
    -- * Bit set type
      BitSet

    -- * Operators
    , (\\)

    -- * Construction
    , empty
    , singleton
    , insert
    , delete

    -- * Query
    , null
    , size
    , member
    , notMember
    , isSubsetOf
    , isProperSubsetOf

    -- * Combine
    , union
    , unions
    , difference
    , intersection

    -- * Transformations
    , map

    -- * Filter
    , filter

    -- * Lists
    , toList
    , fromList
    ) where

import Prelude hiding (null, map, filter)

import Control.Applicative ((<$>))
import Data.Bits (Bits, (.|.), (.&.), complement, bit,
                  testBit, setBit, clearBit, popCount)
import Data.Function (on)
import Data.Monoid (Monoid(..), (<>))
import Text.Read (Read(..), Lexeme(..), lexP, prec, parens)
import qualified Data.Foldable as Foldable
import qualified Data.List as List

import Control.DeepSeq (NFData(..))

import Data.BitSet.Internal (GBitSet(..))

type BitSet = GBitSet

instance Eq (BitSet c a) where
    (==) = (==) `on` _n

instance Ord (BitSet c a) where
    compare = compare `on` _n

instance (Enum a, Read a, Bits c, Num c) => Read (BitSet c a) where
    readPrec = parens . prec 10 $ do
        Ident "fromList" <- lexP
        fromList <$> readPrec

instance (Show a, Num c) => Show (BitSet c a) where
    showsPrec p bs = showParen (p > 10) $
                     showString "fromList " . shows (toList bs)

instance (Enum a, Bits c, Num c) => Monoid (BitSet c a) where
    mempty  = empty
    mappend = union
    mconcat = unions

instance NFData c => NFData (BitSet c a) where
    rnf (BitSet { _n, _bits }) = rnf _n `seq` rnf _bits `seq` ()

instance Num c => Foldable.Foldable (BitSet c) where
    foldMap f (BitSet { _n, _bits }) = go _n 0 where
        go 0 _b = mempty
        go !n b = if _bits `testBit` b
                  then f (toEnum b) <> go (pred n) (succ b)
                  else go n (succ b)

-- | /O(1)/. Is the bit set empty?
null :: BitSet c a -> Bool
null (BitSet { _bits }) = _bits == 0
{-# INLINE null #-}

-- | /O(1)/. The number of elements in the bit set.
size :: BitSet c a -> Int
size = _n
{-# INLINE size #-}

-- | /O(d)/. Ask whether the item is in the bit set.
member :: a -> BitSet c a -> Bool
member x (BitSet { _bits }) = _bits `testBit` fromEnum x
{-# INLINE member #-}

-- | /O(d)/. Ask whether the item is in the bit set.
notMember :: a -> BitSet c a -> Bool
notMember x = not . member x
{-# INLINE notMember #-}

-- | /O(max(n, m))/. Is this a subset? (@s1 isSubsetOf s2@) tells whether
-- @s1@ is a subset of @s2@.
isSubsetOf :: BitSet c a -> BitSet c a -> Bool
isSubsetOf (BitSet { _n = n1, _bits = b1 }) (BitSet { _n = n2, _bits = b2 }) =
    n2 >= n1 && b2 .|. b1 == b2

-- | /O(max(n, m)/. Is this a proper subset? (ie. a subset but not equal).
isProperSubsetOf :: Eq c => BitSet c a -> BitSet c a -> Bool
isProperSubsetOf bs1 bs2 = bs1 `isSubsetOf` bs2 && bs1 /= bs2

-- | The empty bit set.
empty :: (Enum a, Bits c, Num c) => BitSet c a
empty = BitSet { _n = 0, _bits = 0 }
{-# INLINE empty #-}

-- | O(1). Create a singleton set.
singleton :: (Enum a, Bits c, Num c) => a -> BitSet c a
singleton x = BitSet { _n = 1, _bits = bit $! fromEnum x }
{-# INLINE singleton #-}

-- | /O(d)/. Insert an item into the bit set.
insert :: a -> BitSet c a -> BitSet c a
insert x bs@(BitSet { _bits }) =
    let b = _bits `setBit` fromEnum x in bs { _n = popCount b, _bits = b }
{-# INLINE insert #-}

-- | /O(d)/. Delete an item from the bit set.
delete :: a -> BitSet c a -> BitSet c a
delete x bs@(BitSet { _bits }) =
    let b = _bits `clearBit` fromEnum x in bs { _n = popCount b, _bits = b }
{-# INLINE delete #-}

-- | /O(max(m, n))/. The union of two bit sets.
union :: BitSet c a -> BitSet c a -> BitSet c a
union (BitSet { _bits = b1 }) (BitSet { _bits = b2 }) =
    let b = b1 .|. b2 in BitSet { _n = popCount b, _bits = b }

{-# INLINE union #-}

-- | /O(max(m, n))/. The union of a list of bit sets.
unions :: (Enum a, Bits c, Num c) => [BitSet c a] -> BitSet c a
unions = List.foldl' union empty
{-# INLINE unions #-}

-- | /O(max(m, n))/. Difference of two bit sets.
difference :: BitSet c a -> BitSet c a -> BitSet c a
difference (BitSet { _bits = b1 }) (BitSet { _bits = b2 }) =
    let b = b1 .&. complement b2 in BitSet { _n = popCount b, _bits = b }
{-# INLINE difference #-}

-- | /O(max(m, n))/. See 'difference'.
(\\) :: BitSet c a -> BitSet c a -> BitSet c a
(\\) = difference

-- | /O(max(m, n))/. The intersection of two bit sets.
intersection :: BitSet c a -> BitSet c a -> BitSet c a
intersection (BitSet { _bits = b1 }) (BitSet { _bits = b2 }) =
    BitSet { _n = popCount b, _bits = b }
  where
    b = b1 .&. b2
{-# INLINE intersection #-}

-- | /O(d * n)/ Transform this bit set by applying a function to every
-- value. Resulting bit set may be smaller then the original.
map :: (Enum a, Enum b, Bits c, Num c) => (a -> b) -> BitSet c a -> BitSet c b
map f = fromList . List.map f . toList

-- | /O(d * n)/ Filter this bit set by retaining only elements satisfying
-- predicate.
filter :: (Enum a, Bits c, Num c) => (a -> Bool) -> BitSet c a -> BitSet c a
filter f = fromList . List.filter f . toList

-- | /O(d * n)/. Convert the bit set set to a list of elements.
toList :: Num c => BitSet c a -> [a]
toList = Foldable.toList

-- | /O(d * n)/. Make a bit set from a list of elements.
fromList :: (Enum a, Bits c, Num c) => [a] -> BitSet c a
fromList xs = BitSet { _n = popCount b, _bits = b } where
  b = List.foldl' (\i x -> setBit i (fromEnum x)) 0 xs
{-# INLINE fromList #-}
