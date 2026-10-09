let Uploaders = {}

Uploaders.S3 = function(entries, onViewError) {
	entries.forEach(entry => {
		let formData = new FormData()
		let {
			url,
			fields
		} = entry.meta
		Object.entries(fields).forEach(([key, val]) => formData.append(key, val))
		formData.append("file", entry.file)
		let xhr = new XMLHttpRequest()
		onViewError(() => xhr.abort())
		xhr.onload = () => xhr.status === 204 ? entry.progress(100) : entry.error()
		xhr.onerror = () => entry.error()
		xhr.upload.addEventListener("progress", (event) => {
			if (event.lengthComputable) {
				let percent = Math.round((event.loaded / event.total) * 100)
				if (percent < 100) {
					entry.progress(percent)
				}
			}
		})

		xhr.open("POST", url, true)
		xhr.send(formData)
	})
}

// Supabase Storage signed-upload: PUT the raw file bytes to the signed URL.
// `entry.meta` carries {url, headers}; the signed token is already in the URL.
Uploaders.Supabase = function(entries, onViewError) {
	entries.forEach(entry => {
		let { url, headers } = entry.meta
		let xhr = new XMLHttpRequest()
		onViewError(() => xhr.abort())
		xhr.onload = () => (xhr.status >= 200 && xhr.status < 300) ? entry.progress(100) : entry.error()
		xhr.onerror = () => entry.error()
		xhr.upload.addEventListener("progress", (event) => {
			if (event.lengthComputable) {
				let percent = Math.round((event.loaded / event.total) * 100)
				if (percent < 100) {
					entry.progress(percent)
				}
			}
		})

		xhr.open("PUT", url, true)
		xhr.setRequestHeader("Content-Type", entry.file.type)
		Object.entries(headers || {}).forEach(([key, val]) => xhr.setRequestHeader(key, val))
		xhr.send(entry.file)
	})
}

export {Uploaders}
