#include "voxel_kernels.h"

#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/color.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

#include <algorithm>
#include <array>
#include <cstring>
#include <vector>

using namespace godot;

namespace ourcraft {

namespace {

constexpr int S = 32;
constexpr int AREA = S * S;
constexpr int VOLUME = S * S * S;

// Must match Mesher.SHADE and Mesher.AXES in render/mesher.gd.
constexpr float SHADE[6] = { 0.88f, 0.94f, 1.0f, 0.72f, 0.82f, 0.9f };
struct Axis {
	int u, v;
	bool flip;
};
constexpr Axis AXES[3] = { { 1, 2, false }, { 0, 2, true }, { 0, 1, false } };

using Slice = std::array<uint8_t, AREA>;

inline int index(int x, int y, int z) {
	return x + y * S + z * AREA;
}

// Layer i along axis d, laid out as u + v * S (see AXES).
void extract(const uint8_t *data, int d, int i, Slice &out) {
	if (d == 2) {
		std::memcpy(out.data(), data + i * AREA, AREA);
	} else if (d == 1) {
		for (int z = 0; z < S; z++) {
			std::memcpy(out.data() + z * S, data + i * S + z * AREA, S);
		}
	} else {
		int j = 0;
		for (int z = 0; z < S; z++) {
			for (int y = 0; y < S; y++) {
				out[j++] = data[index(i, y, z)];
			}
		}
	}
}

struct Output {
	std::vector<Vector3> verts;
	std::vector<Vector3> normals;
	std::vector<Color> colors;
	std::vector<int32_t> indices;
	std::vector<Vector3> faces;
};

void emit_quad(Output &out, const Vector3 &p, const Vector3 &du, const Vector3 &dv, int winding,
		const Vector3 &normal, const Color &col) {
	const int32_t base = (int32_t)out.verts.size();
	const Vector3 a = p;
	const Vector3 b = p + du;
	const Vector3 c = p + du + dv;
	const Vector3 e = p + dv;
	out.verts.insert(out.verts.end(), { a, b, c, e });
	for (int k = 0; k < 4; k++) {
		out.normals.push_back(normal);
		out.colors.push_back(col);
	}
	// Godot treats clockwise triangles as front-facing.
	if (winding > 0) {
		out.indices.insert(out.indices.end(), { base, base + 3, base + 2, base, base + 2, base + 1 });
		out.faces.insert(out.faces.end(), { a, e, c, a, c, b });
	} else {
		out.indices.insert(out.indices.end(), { base, base + 1, base + 2, base, base + 2, base + 3 });
		out.faces.insert(out.faces.end(), { a, b, c, a, c, e });
	}
}

void greedy(std::array<int32_t, AREA> &mask, int d, int i, int dir, const Vector3 &origin,
		const std::vector<Color> &palette, float cell_m, Output &out) {
	const int u = AXES[d].u;
	const int v = AXES[d].v;
	const int winding = AXES[d].flip ? -dir : dir;
	Vector3 normal;
	normal[d] = (real_t)dir;
	const float shade = SHADE[d * 2 + (dir > 0 ? 0 : 1)];
	for (int vv = 0; vv < S; vv++) {
		int uu = 0;
		while (uu < S) {
			const int32_t c = mask[uu + vv * S];
			if (c == 0) {
				uu++;
				continue;
			}
			int w = 1;
			while (uu + w < S && mask[uu + w + vv * S] == c) {
				w++;
			}
			int h = 1;
			bool grow = true;
			while (grow && vv + h < S) {
				const int row = (vv + h) * S;
				for (int k = 0; k < w; k++) {
					if (mask[uu + k + row] != c) {
						grow = false;
						break;
					}
				}
				if (grow) {
					h++;
				}
			}
			for (int hv = 0; hv < h; hv++) {
				std::fill_n(mask.begin() + uu + (vv + hv) * S, w, 0);
			}
			Vector3 p = origin;
			p[d] += (real_t)i;
			p[u] += (real_t)uu;
			p[v] += (real_t)vv;
			Vector3 du;
			du[u] = (real_t)w;
			Vector3 dv;
			dv[v] = (real_t)h;
			Color col = palette[(c - 1) % palette.size()] * shade;
			col.a = 1.0f;
			emit_quad(out, p * cell_m, du * cell_m, dv * cell_m, winding, normal, col);
			uu += w;
		}
	}
}

template <typename T, typename P>
P to_packed(const std::vector<T> &src) {
	P out;
	out.resize((int64_t)src.size());
	if (!src.empty()) {
		std::memcpy(out.ptrw(), src.data(), src.size() * sizeof(T));
	}
	return out;
}

// Small fast generator for the slicer (splitmix64).
struct Rng {
	uint64_t state;
	uint64_t next() {
		uint64_t z = (state += 0x9e3779b97f4a7c15ULL);
		z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ULL;
		z = (z ^ (z >> 27)) * 0x94d049bb133111ebULL;
		return z ^ (z >> 31);
	}
	int64_t below(int64_t n) { return (int64_t)(next() % (uint64_t)n); }
};

// Grows the frontier cells' labels into unlabelled solid neighbours,
// picking the next cell to grow from at random.
void grow(const uint8_t *cells, int64_t sx, int64_t sy, int64_t sz, int32_t *labels,
		std::vector<int64_t> &frontier, Rng &rng) {
	const int64_t sxy = sx * sy;
	while (!frontier.empty()) {
		const size_t j = (size_t)rng.below((int64_t)frontier.size());
		const int64_t i = frontier[j];
		frontier[j] = frontier.back();
		frontier.pop_back();
		const int32_t label = labels[i];
		const int64_t x = i % sx;
		const int64_t y = (i / sx) % sy;
		const int64_t z = i / sxy;
		const int64_t nbs[6] = {
			x > 0 ? i - 1 : -1, x < sx - 1 ? i + 1 : -1,
			y > 0 ? i - sx : -1, y < sy - 1 ? i + sx : -1,
			z > 0 ? i - sxy : -1, z < sz - 1 ? i + sxy : -1,
		};
		for (int64_t nb : nbs) {
			if (nb >= 0 && cells[nb] != 0 && labels[nb] < 0) {
				labels[nb] = label;
				frontier.push_back(nb);
			}
		}
	}
}

} // namespace

void VoxelKernels::_bind_methods() {
	ClassDB::bind_method(D_METHOD("fill_chunk", "data", "lmin", "lmax", "value"),
			&VoxelKernels::fill_chunk);
	ClassDB::bind_method(D_METHOD("mesh_chunk", "input", "key", "palette", "cell_m"),
			&VoxelKernels::mesh_chunk);
	ClassDB::bind_method(D_METHOD("gather_box", "box", "dims", "olo", "c", "datas", "bases"),
			&VoxelKernels::gather_box);
	ClassDB::bind_method(D_METHOD("slice_pieces", "cells", "dims", "seeds", "max_pieces", "rng_seed"),
			&VoxelKernels::slice_pieces);
}

Array VoxelKernels::fill_chunk(const PackedByteArray &data, const Vector3i &lmin, const Vector3i &lmax,
		int64_t value) {
	PackedByteArray result = data;
	int64_t delta = 0;
	bool changed = false;
	if (result.size() == VOLUME) {
		uint8_t *cells = result.ptrw();
		const uint8_t val = (uint8_t)value;
		for (int z = lmin.z; z < lmax.z; z++) {
			for (int y = lmin.y; y < lmax.y; y++) {
				uint8_t *row = cells + y * S + z * AREA;
				for (int x = lmin.x; x < lmax.x; x++) {
					const uint8_t old = row[x];
					if (old == val) {
						continue;
					}
					changed = true;
					if (old == 0) {
						delta++;
					} else if (val == 0) {
						delta--;
					}
					row[x] = val;
				}
			}
		}
	}
	Array out;
	out.append(result);
	out.append(delta);
	out.append(changed);
	return out;
}

Dictionary VoxelKernels::mesh_chunk(const Array &input, const Vector3i &key, const Array &palette_in,
		double cell_m_in) {
	if (input.size() != 7 || input[0].get_type() != Variant::PACKED_BYTE_ARRAY) {
		return Dictionary();
	}
	const PackedByteArray own = input[0];
	if (own.size() != VOLUME || palette_in.is_empty()) {
		return Dictionary();
	}
	PackedByteArray neighbours[6];
	bool has[6];
	for (int n = 0; n < 6; n++) {
		has[n] = input[n + 1].get_type() == Variant::PACKED_BYTE_ARRAY;
		if (has[n]) {
			neighbours[n] = input[n + 1];
			has[n] = neighbours[n].size() == VOLUME;
		}
	}
	std::vector<Color> palette;
	for (int64_t k = 0; k < palette_in.size(); k++) {
		palette.push_back(palette_in[k]);
	}
	const float cell_m = (float)cell_m_in;
	const uint8_t *data = own.ptr();

	uint8_t uniform = data[0];
	if (uniform != 0) {
		for (int k = 1; k < VOLUME; k++) {
			if (data[k] != uniform) {
				uniform = 0;
				break;
			}
		}
	}
	Slice full;
	full.fill(uniform);
	Slice empty;
	empty.fill(0);

	Output out;
	const Vector3 origin((real_t)(key.x * S), (real_t)(key.y * S), (real_t)(key.z * S));
	std::array<int32_t, AREA> pos_mask;
	std::array<int32_t, AREA> neg_mask;
	Slice below;
	Slice above;

	for (int d = 0; d < 3; d++) {
		const int neg = d * 2;
		const int pos = d * 2 + 1;
		if (has[neg]) {
			extract(neighbours[neg].ptr(), d, S - 1, below);
		} else {
			below = empty;
		}
		for (int i = 0; i <= S; i++) {
			if (uniform != 0 && i > 0 && i < S) {
				continue;
			}
			if (i == S) {
				if (has[pos]) {
					extract(neighbours[pos].ptr(), d, 0, above);
				} else {
					above = empty;
				}
				if (uniform != 0) {
					below = full;
				}
			} else if (uniform != 0) {
				above = full;
			} else {
				extract(data, d, i, above);
			}
			if (below == above) {
				continue;
			}
			bool any = false;
			for (int j = 0; j < AREA; j++) {
				const uint8_t a = below[j];
				const uint8_t b = above[j];
				if (a != 0 && b == 0) {
					pos_mask[j] = a;
					neg_mask[j] = 0;
					any = true;
				} else if (b != 0 && a == 0) {
					neg_mask[j] = b;
					pos_mask[j] = 0;
					any = true;
				} else {
					pos_mask[j] = 0;
					neg_mask[j] = 0;
				}
			}
			// Boundary planes only carry this chunk's own faces.
			if (any && i > 0) {
				greedy(pos_mask, d, i, 1, origin, palette, cell_m, out);
			}
			if (any && i < S) {
				greedy(neg_mask, d, i, -1, origin, palette, cell_m, out);
			}
			below = above;
		}
	}

	if (out.indices.empty()) {
		return Dictionary();
	}
	Array arrays;
	arrays.resize(Mesh::ARRAY_MAX);
	arrays[Mesh::ARRAY_VERTEX] = to_packed<Vector3, PackedVector3Array>(out.verts);
	arrays[Mesh::ARRAY_NORMAL] = to_packed<Vector3, PackedVector3Array>(out.normals);
	arrays[Mesh::ARRAY_COLOR] = to_packed<Color, PackedColorArray>(out.colors);
	arrays[Mesh::ARRAY_INDEX] = to_packed<int32_t, PackedInt32Array>(out.indices);
	Dictionary result;
	result["arrays"] = arrays;
	result["faces"] = to_packed<Vector3, PackedVector3Array>(out.faces);
	return result;
}

PackedByteArray VoxelKernels::gather_box(const PackedByteArray &box, const Vector3i &dims,
		const Vector3i &olo, int64_t c, const Array &datas, const Array &bases) {
	PackedByteArray result = box;
	const int64_t sx = dims.x, sy = dims.y, sz = dims.z;
	if (result.size() != sx * sy * sz || c < 1 || c > S || (c & (c - 1)) != 0) {
		return result;
	}
	uint8_t *out = result.ptrw();
	uint32_t votes[256];
	for (int64_t k = 0; k < datas.size() && k < bases.size(); k++) {
		const PackedByteArray data = datas[k];
		const Vector3i base = bases[k];
		if (data.size() != VOLUME) {
			continue;
		}
		const uint8_t *cells = data.ptr();
		// Coarse cells never straddle chunks: both are aligned powers of two.
		for (int z = 0; z < S; z += (int)c) {
			for (int y = 0; y < S; y += (int)c) {
				for (int x = 0; x < S; x += (int)c) {
					uint8_t best = 0;
					if (c == 1) {
						best = cells[index(x, y, z)];
					} else {
						std::memset(votes, 0, sizeof(votes));
						uint32_t best_n = 0;
						for (int dz = 0; dz < c; dz++) {
							for (int dy = 0; dy < c; dy++) {
								const uint8_t *row = cells + index(x, y + dy, z + dz);
								for (int dx = 0; dx < c; dx++) {
									const uint8_t v = row[dx];
									// Ties go to the first value to reach the count.
									if (v != 0 && ++votes[v] > best_n) {
										best_n = votes[v];
										best = v;
									}
								}
							}
						}
					}
					if (best == 0) {
						continue;
					}
					const int64_t qx = (base.x + x) / c - olo.x;
					const int64_t qy = (base.y + y) / c - olo.y;
					const int64_t qz = (base.z + z) / c - olo.z;
					if (qx < 0 || qy < 0 || qz < 0 || qx >= sx || qy >= sy || qz >= sz) {
						continue;
					}
					out[qx + sx * (qy + sy * qz)] = best;
				}
			}
		}
	}
	return result;
}

Array VoxelKernels::slice_pieces(const PackedByteArray &cells, const Vector3i &dims, int64_t seeds,
		int64_t max_pieces, int64_t rng_seed) {
	const int64_t n = cells.size();
	PackedInt32Array labels;
	labels.resize(n);
	int32_t *lab = labels.ptrw();
	std::fill(lab, lab + n, -1);
	Array result;
	if (n != (int64_t)dims.x * dims.y * dims.z) {
		result.append(labels);
		result.append(0);
		return result;
	}
	const uint8_t *c = cells.ptr();
	std::vector<int64_t> solid;
	for (int64_t i = 0; i < n; i++) {
		if (c[i] != 0) {
			solid.push_back(i);
		}
	}
	int32_t count = 0;
	if (!solid.empty()) {
		Rng rng{ (uint64_t)rng_seed };
		std::vector<int64_t> frontier;
		const int64_t want = std::min(seeds, max_pieces);
		for (int64_t k = 0; k < want; k++) {
			const int64_t i = solid[(size_t)rng.below((int64_t)solid.size())];
			if (lab[i] < 0) {
				lab[i] = count++;
				frontier.push_back(i);
			}
		}
		grow(c, dims.x, dims.y, dims.z, lab, frontier, rng);
		for (int64_t i : solid) {
			if (lab[i] < 0) {
				if (count < max_pieces) {
					count++;
				}
				lab[i] = count - 1;
				frontier.push_back(i);
				grow(c, dims.x, dims.y, dims.z, lab, frontier, rng);
			}
		}
	}
	result.append(labels);
	result.append(count);
	return result;
}

} // namespace ourcraft
